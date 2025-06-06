#!/bin/sh

# sudo-run0: A compatibility wrapper around systemd's run0 utility
# that can be used as a drop-in sudo replacement

# Version and constants
readonly VERSION="1.6"
readonly USAGE="usage: sudo [-u user] [-g group] [-i] [-s] [-H] [-E] [--preserve-env[=list]] [-n] [-b] [-k] [-K] [-c command] [-D directory] [-P] [-l] [-v] [-h] [-V] command [args...]"

# Global variables for parsed options
RUN0_ARGS=""
COMMAND_ARGS=""

# Utility functions
die() {
    printf "sudo: %s\n" "$1" >&2
    exit 1
}

show_usage() {
    echo "$USAGE" >&2
}

show_help() {
    cat << 'EOF'
usage: sudo [-u user] [-g group] [-i] [-s] [-H] [-E] [--preserve-env[=list]] [-n] [-b] [-k] [-K] [-c command] [-D directory] [-P] [-l] [-v] [-h] [-V] command [args...]

Options:
  -u, --user USER               run command as specified user
  -g, --group GROUP             run command as specified group
  -i, --login                   run shell as target user's login shell
  -s, --shell                   run shell as target user
  -H, --set-home                set HOME variable to target user's home directory
  -E, --preserve-env            preserve all environment variables
      --preserve-env=list       preserve specific environment variables (comma-separated)
  -n, --non-interactive         non-interactive mode (fail if authentication needed)
  -b, --background              run command in background
  -k, --reset-timestamp         reset authentication timestamp
  -K, --remove-timestamp        remove authentication timestamp
  -c, --command=command         run command via shell
  -D, --chdir=directory         change working directory before running command
  -P, --preserve-groups         preserve supplementary group memberships
  -l, --list                    list user's privileges
  -v, --validate                update user's timestamp
  -h, --help                    display this help message
  -V, --version                 display version information
EOF
}

show_version() {
    echo "sudo-run0 compatibility wrapper $VERSION"
    echo "This is a wrapper around systemd run0 for sudo compatibility"
    echo "Underlying run0 version:"
    run0 --version 2>/dev/null || echo "run0 version unavailable"
}

# Get user information
get_user_shell() {
    local username="${1:-root}"
    getent passwd "$username" 2>/dev/null | cut -d: -f7
}

get_user_home() {
    local username="${1:-root}"
    getent passwd "$username" 2>/dev/null | cut -d: -f6
}

# Validate and normalize shell
validate_shell() {
    local shell="$1"
    case "$(basename "$shell")" in
        nologin|false|"")
            echo "/bin/sh"
            ;;
        *)
            echo "$shell"
            ;;
    esac
}

# Get target shell for user (consolidated function)
get_target_shell() {
    local username="${1:-root}"
    local shell
    shell=$(get_user_shell "$username")
    validate_shell "$shell"
}

# Set HOME directory for target user (consolidated function)
set_target_home() {
    local username="${1:-root}"
    local target_home
    
    if [ "$username" = "root" ]; then
        echo "--setenv=HOME=/root"
    else
        target_home=$(get_user_home "$username")
        if [ -n "$target_home" ]; then
            echo "--setenv=HOME=$target_home"
        fi
    fi
}

# Environment variable collection using run0's automatic value pickup
collect_env_vars() {
    local preserve_mode="$1"
    local specific_vars="$2"
    
    case "$preserve_mode" in
        "all")
            # Get all environment variables, excluding only the most problematic ones
            # Use run0's --setenv=NAME feature which automatically picks up values
            env | while IFS='=' read -r name value; do
                # Skip variables that would interfere with the new environment
                case "$name" in
                    # Skip shell-specific variables that should be reset
                    PWD|OLDPWD|SHLVL|_|PS1|PS2|PS3|PS4) continue ;;
                    # Skip sudo-specific variables
                    SUDO_*) continue ;;
                    # Skip if name is empty (shouldn't happen, but be safe)
                    "") continue ;;
                    # Pass everything else using run0's automatic value pickup
                    *) printf " --setenv=%s" "$name" ;;
                esac
            done
            ;;
        "specific")
            # Handle specific variables - much simpler now
            echo "$specific_vars" | tr ',' '\n' | while read -r var; do
                # Remove whitespace
                var=$(echo "$var" | tr -d ' \t')
                if [ -n "$var" ] && [ -n "$(eval "echo \${$var+x}")" ]; then
                    printf " --setenv=%s" "$var"
                fi
            done
            ;;
    esac
}

# Handle special sudo modes
handle_special_modes() {
    local list_mode="$1"
    local validate_mode="$2"
    local reset_timestamp="$3"
    local remove_timestamp="$4"
    
    if [ "$list_mode" = true ]; then
        echo "User $(whoami) may run the following commands:"
        echo "    (ALL) ALL"
        exit 0
    fi
    
    if [ "$validate_mode" = true ]; then
        # Trigger authentication like real sudo -v
        run0 /bin/true >/dev/null 2>&1
        exit $?
    fi
    
    if [ "$reset_timestamp" = true ] || [ "$remove_timestamp" = true ]; then
        # Simulate timestamp reset by triggering a failing auth
        # This will effectively "reset" the polkit timestamp
        run0 --no-ask-password /bin/false >/dev/null 2>&1
        exit 0
    fi
}

# Configure login shell environment (refactored)
setup_login_shell() {
    local target_user="$1"
    local shell_args=""
    
    # Get and set target shell
    local target_shell
    target_shell=$(get_target_shell "$target_user")
    shell_args="$shell_args --setenv=SHELL=$target_shell"
    
    # Set HOME directory
    local home_arg
    home_arg=$(set_target_home "$target_user")
    shell_args="$shell_args $home_arg"
    
    echo "$shell_args"
}

# Determine final command to execute (consolidated logic)
determine_final_command() {
    local target_user="$1"
    local login_shell="$2"
    local shell_mode="$3"
    local shell_command="$4"
    shift 4
    
    # Handle shell command (-c option) - highest priority
    if [ -n "$shell_command" ]; then
        local target_shell
        target_shell=$(get_target_shell "$target_user")
        set -- "$target_shell" -c "$shell_command"
        echo "$*"
        return
    fi
    
    # Handle login shell or shell mode when no command specified
    if ([ "$login_shell" = true ] || [ "$shell_mode" = true ]) && [ $# -eq 0 ]; then
        local target_shell
        target_shell=$(get_target_shell "$target_user")
        echo "$target_shell"
        return
    fi
    
    # Return any remaining arguments as-is
    echo "$*"
}

# Parse command line arguments
parse_arguments() {
    local target_user=""
    local target_group=""
    local login_shell=false
    local shell_mode=false
    local set_home=false
    local list_mode=false
    local validate_mode=false
    local preserve_env=""
    local preserve_env_vars=""
    local non_interactive=false
    local background_mode=false
    local reset_timestamp=false
    local remove_timestamp=false
    local shell_command=""
    local working_directory=""
    local preserve_groups=false
    
    # Always disable visual changes for sudo compatibility
    RUN0_ARGS="--shell-prompt-prefix= --background="
    
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -V|--version)
                show_version
                exit 0
                ;;
            -l|--list)
                list_mode=true
                shift
                ;;
            -v|--validate)
                validate_mode=true
                shift
                ;;
            -k|--reset-timestamp)
                reset_timestamp=true
                shift
                ;;
            -K|--remove-timestamp)
                remove_timestamp=true
                shift
                ;;
            -s|--shell)
                shell_mode=true
                shift
                ;;
            -H|--set-home)
                set_home=true
                shift
                ;;
            -n|--non-interactive)
                non_interactive=true
                shift
                ;;
            -b|--background)
                background_mode=true
                shift
                ;;
            -P|--preserve-groups)
                preserve_groups=true
                shift
                ;;
            -c|--command)
                if [ -z "$2" ]; then
                    echo "sudo: option requires an argument -- c" >&2
                    show_usage
                    exit 1
                fi
                shell_command="$2"
                shift 2
                # When using -c, ignore remaining arguments (like real sudo does)
                break
                ;;
            -c*)
                shell_command="${1#-c}"
                shift
                # When using -c, ignore remaining arguments (like real sudo does)
                break
                ;;
            -D|--chdir)
                if [ -z "$2" ]; then
                    echo "sudo: option requires an argument -- D" >&2
                    show_usage
                    exit 1
                fi
                working_directory="$2"
                shift 2
                ;;
            -D*)
                working_directory="${1#-D}"
                shift
                ;;
            -E|--preserve-env)
                preserve_env="all"
                shift
                ;;
            --preserve-env=*)
                preserve_env="specific"
                preserve_env_vars="${1#--preserve-env=}"
                if [ -z "$preserve_env_vars" ]; then
                    echo "sudo: --preserve-env requires a variable list" >&2
                    show_usage
                    exit 1
                fi
                shift
                ;;
            -u|--user)
                if [ -z "$2" ]; then
                    echo "sudo: option requires an argument -- u" >&2
                    show_usage
                    exit 1
                fi
                target_user="$2"
                shift 2
                ;;
            -u*)
                target_user="${1#-u}"
                shift
                ;;
            -g|--group)
                if [ -z "$2" ]; then
                    echo "sudo: option requires an argument -- g" >&2
                    show_usage
                    exit 1
                fi
                target_group="$2"
                shift 2
                ;;
            -g*)
                target_group="${1#-g}"
                shift
                ;;
            -i|--login)
                login_shell=true
                shift
                ;;
            --)
                shift
                break
                ;;
            -*)
                echo "sudo: invalid option -- '${1#-}'" >&2
                show_usage
                exit 1
                ;;
            *)
                # Non-option argument
                break
                ;;
        esac
    done
    
    # Handle special modes first
    handle_special_modes "$list_mode" "$validate_mode" "$reset_timestamp" "$remove_timestamp"
    
    # Set default target user
    target_user="${target_user:-root}"
    
    # Build run0 arguments
    RUN0_ARGS="$RUN0_ARGS --user=$target_user"
    [ -n "$target_group" ] && RUN0_ARGS="$RUN0_ARGS --group=$target_group"
    
    # Handle working directory change
    if [ -n "$working_directory" ]; then
        # Validate that directory exists and is accessible
        if [ ! -d "$working_directory" ]; then
            echo "sudo: $working_directory: No such file or directory" >&2
            exit 1
        fi
        RUN0_ARGS="$RUN0_ARGS --chdir=$working_directory"
    fi
    
    # Handle non-interactive mode
    if [ "$non_interactive" = true ]; then
        RUN0_ARGS="$RUN0_ARGS --no-ask-password"
    fi
    
    # Handle preserve groups (limited implementation)
    if [ "$preserve_groups" = true ]; then
        local current_groups
        current_groups=$(id -G 2>/dev/null)
        if [ -n "$current_groups" ]; then
            RUN0_ARGS="$RUN0_ARGS --setenv=SUDO_GROUPS=$current_groups"
        fi
    fi
    
    # Handle environment variable preservation
    if [ -n "$preserve_env" ]; then
        local env_args
        env_args=$(collect_env_vars "$preserve_env" "$preserve_env_vars")
        RUN0_ARGS="$RUN0_ARGS$env_args"
    fi
    
    # Handle set-home option (using consolidated function)
    if [ "$set_home" = true ]; then
        local home_arg
        home_arg=$(set_target_home "$target_user")
        RUN0_ARGS="$RUN0_ARGS $home_arg"
    fi
    
    # Handle login shell (using refactored function)
    if [ "$login_shell" = true ]; then
        local shell_args
        shell_args=$(setup_login_shell "$target_user")
        RUN0_ARGS="$RUN0_ARGS$shell_args"
    fi
    
    # Handle shell command (-c option) - special case with direct execution
    if [ -n "$shell_command" ]; then
        local target_shell
        target_shell=$(get_target_shell "$target_user")
        # Execute directly with proper quoting
        if [ "$BACKGROUND_MODE" = true ]; then
            nohup run0 $RUN0_ARGS "$target_shell" -c "$shell_command" >/dev/null 2>&1 &
            exit 0
        else
            exec run0 $RUN0_ARGS "$target_shell" -c "$shell_command"
        fi
    fi
    
    # Determine final command for other cases
    local final_command
    final_command=$(determine_final_command "$target_user" "$login_shell" "$shell_mode" "" "$@")
    
    # Set remaining command arguments
    COMMAND_ARGS="$final_command"
    
    # Store background mode for main execution
    if [ "$background_mode" = true ]; then
        BACKGROUND_MODE=true
    fi
}

# Main execution
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Execute run0 with our arguments
    if [ -n "$COMMAND_ARGS" ]; then
        if [ "$BACKGROUND_MODE" = true ]; then
            # Run in background - use nohup to properly detach
            nohup run0 $RUN0_ARGS $COMMAND_ARGS >/dev/null 2>&1 &
            exit 0
        else
            exec run0 $RUN0_ARGS $COMMAND_ARGS
        fi
    else
        if [ "$BACKGROUND_MODE" = true ]; then
            nohup run0 $RUN0_ARGS >/dev/null 2>&1 &
            exit 0
        else
            exec run0 $RUN0_ARGS
        fi
    fi
}

# Script entry point
main "$@"
