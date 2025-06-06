#!/run/current-system/sw/bin/bash

# sudo-run0: A compatibility wrapper around systemd's run0 utility
# that can be used as a drop-in sudo replacement

# Version and constants
readonly VERSION="1.7"
readonly USAGE="usage: sudo [-u user] [-g group] [-i] [-s] [-H] [-E] [--preserve-env[=list]] [-n] [-b] [-k] [-K] [-c command] [-D directory] [-P] [-l] [-v] [-h] [-V] command [args...]"

# Global variables for parsed options
declare -A OPTIONS=(
    [target_user]=""
    [target_group]=""
    [login_shell]=false
    [shell_mode]=false
    [set_home]=false
    [list_mode]=false
    [validate_mode]=false
    [preserve_env]=""
    [preserve_env_vars]=""
    [non_interactive]=false
    [background_mode]=false
    [reset_timestamp]=false
    [remove_timestamp]=false
    [shell_command]=""
    [working_directory]=""
    [preserve_groups]=false
)

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
    if [[ "${OPTIONS[list_mode]}" == true ]]; then
        echo "User $(whoami) may run the following commands:"
        echo "    (ALL) ALL"
        exit 0
    fi
    
    if [[ "${OPTIONS[validate_mode]}" == true ]]; then
        # Trigger authentication like real sudo -v
        run0 /bin/true >/dev/null 2>&1
        exit $?
    fi
    
    if [[ "${OPTIONS[reset_timestamp]}" == true ]] || [[ "${OPTIONS[remove_timestamp]}" == true ]]; then
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
    shift
    
    # Handle shell command (-c option) - highest priority
    if [[ -n "${OPTIONS[shell_command]}" ]]; then
        local target_shell
        target_shell=$(get_target_shell "$target_user")
        set -- "$target_shell" -c "${OPTIONS[shell_command]}"
        echo "$*"
        return
    fi
    
    # Handle login shell or shell mode when no command specified
    if ([[ "${OPTIONS[login_shell]}" == true ]] || [[ "${OPTIONS[shell_mode]}" == true ]]) && [ $# -eq 0 ]; then
        local target_shell
        target_shell=$(get_target_shell "$target_user")
        echo "$target_shell"
        return
    fi
    
    # Return any remaining arguments as-is
    echo "$*"
}

# Validate option conflicts and set appropriate precedence
validate_and_resolve_conflicts() {
    # Validate working directory if specified
    if [[ -n "${OPTIONS[working_directory]}" ]]; then
        if [[ ! -d "${OPTIONS[working_directory]}" ]]; then
            die "${OPTIONS[working_directory]}: No such file or directory"
        fi
    fi
    
    # Validate user existence if specified
    if [[ -n "${OPTIONS[target_user]}" ]] && [[ "${OPTIONS[target_user]}" != "root" ]]; then
        if ! getent passwd "${OPTIONS[target_user]}" >/dev/null 2>&1; then
            die "unknown user: ${OPTIONS[target_user]}"
        fi
    fi
    
    # Validate group existence if specified
    if [[ -n "${OPTIONS[target_group]}" ]]; then
        if ! getent group "${OPTIONS[target_group]}" >/dev/null 2>&1; then
            die "unknown group: ${OPTIONS[target_group]}"
        fi
    fi
}

# Enhanced argument parsing using GNU getopt
parse_arguments() {
    # Define short and long options
    # + prefix means stop at first non-option (critical for sudo behavior)
    local short_opts="+u:g:c:D:isHEnbkKPlvhV"
    local long_opts="user:,group:,command:,chdir:,login,shell,set-home,preserve-env::,non-interactive,background,reset-timestamp,remove-timestamp,preserve-groups,list,validate,help,version"
    
    # Parse arguments using getopt
    local parsed_args
    if ! parsed_args=$(getopt -o "$short_opts" -l "$long_opts" -n "sudo" -- "$@"); then
        show_usage
        exit 1
    fi
    
    # Set parsed arguments
    eval set -- "$parsed_args"
    
    # Process parsed options
    while true; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -V|--version)
                show_version
                exit 0
                ;;
            -u|--user)
                OPTIONS[target_user]="$2"
                shift 2
                ;;
            -g|--group)
                OPTIONS[target_group]="$2"
                shift 2
                ;;
            -c|--command)
                OPTIONS[shell_command]="$2"
                shift 2
                # When using -c, remaining args after -- are ignored (like real sudo)
                break
                ;;
            -D|--chdir)
                OPTIONS[working_directory]="$2"
                shift 2
                ;;
            -i|--login)
                OPTIONS[login_shell]=true
                shift
                ;;
            -s|--shell)
                OPTIONS[shell_mode]=true
                shift
                ;;
            -H|--set-home)
                OPTIONS[set_home]=true
                shift
                ;;
            -E|--preserve-env)
                if [[ "$1" == "--preserve-env" && -n "$2" ]]; then
                    # --preserve-env with separate argument (shouldn't happen with ::)
                    OPTIONS[preserve_env]="specific"
                    OPTIONS[preserve_env_vars]="$2"
                    shift 2
                elif [[ "$1" == --preserve-env=* ]]; then
                    # --preserve-env=list format
                    OPTIONS[preserve_env]="specific"
                    OPTIONS[preserve_env_vars]="${1#--preserve-env=}"
                    shift 1
                else
                    # -E format (preserve all) or --preserve-env without argument
                    OPTIONS[preserve_env]="all"
                    shift 1
                fi
                ;;
            -n|--non-interactive)
                OPTIONS[non_interactive]=true
                shift
                ;;
            -b|--background)
                OPTIONS[background_mode]=true
                shift
                ;;
            -k|--reset-timestamp)
                OPTIONS[reset_timestamp]=true
                shift
                ;;
            -K|--remove-timestamp)
                OPTIONS[remove_timestamp]=true
                shift
                ;;
            -P|--preserve-groups)
                OPTIONS[preserve_groups]=true
                shift
                ;;
            -l|--list)
                OPTIONS[list_mode]=true
                shift
                ;;
            -v|--validate)
                OPTIONS[validate_mode]=true
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                die "internal error in argument parsing"
                ;;
        esac
    done
    
    # Validate options and resolve conflicts
    validate_and_resolve_conflicts
    
    # Handle special modes first
    handle_special_modes
    
    # Set default target user
    if [[ -z "${OPTIONS[target_user]}" ]]; then
        OPTIONS[target_user]="root"
    fi
    
    # Build run0 arguments
    build_run0_args
    
    # Handle shell command (-c option) - special case with direct execution
    if [[ -n "${OPTIONS[shell_command]}" ]]; then
        local target_shell
        target_shell=$(get_target_shell "${OPTIONS[target_user]}")
        # Execute directly with proper quoting
        if [[ "${OPTIONS[background_mode]}" == true ]]; then
            nohup run0 $RUN0_ARGS "$target_shell" -c "${OPTIONS[shell_command]}" >/dev/null 2>&1 &
            exit 0
        else
            exec run0 $RUN0_ARGS "$target_shell" -c "${OPTIONS[shell_command]}"
        fi
    fi
    
    # Determine final command
    local final_command
    final_command=$(determine_final_command "${OPTIONS[target_user]}" "$@")
    
    # Set remaining command arguments
    COMMAND_ARGS="$final_command"
}

# Build run0 arguments based on parsed options
build_run0_args() {
    # Always disable visual changes for sudo compatibility
    RUN0_ARGS="--shell-prompt-prefix= --background="
    
    # Add user specification
    RUN0_ARGS="$RUN0_ARGS --user=${OPTIONS[target_user]}"
    
    # Add group if specified
    if [[ -n "${OPTIONS[target_group]}" ]]; then
        RUN0_ARGS="$RUN0_ARGS --group=${OPTIONS[target_group]}"
    fi
    
    # Handle working directory change
    if [[ -n "${OPTIONS[working_directory]}" ]]; then
        RUN0_ARGS="$RUN0_ARGS --chdir=${OPTIONS[working_directory]}"
    fi
    
    # Handle non-interactive mode
    if [[ "${OPTIONS[non_interactive]}" == true ]]; then
        RUN0_ARGS="$RUN0_ARGS --no-ask-password"
    fi
    
    # Handle preserve groups (limited implementation)
    if [[ "${OPTIONS[preserve_groups]}" == true ]]; then
        local current_groups
        current_groups=$(id -G 2>/dev/null)
        if [[ -n "$current_groups" ]]; then
            RUN0_ARGS="$RUN0_ARGS --setenv=SUDO_GROUPS=$current_groups"
        fi
    fi
    
    # Handle environment variable preservation
    if [[ -n "${OPTIONS[preserve_env]}" ]]; then
        local env_args
        env_args=$(collect_env_vars "${OPTIONS[preserve_env]}" "${OPTIONS[preserve_env_vars]}")
        RUN0_ARGS="$RUN0_ARGS$env_args"
    fi
    
    # Handle set-home option
    if [[ "${OPTIONS[set_home]}" == true ]]; then
        local home_arg
        home_arg=$(set_target_home "${OPTIONS[target_user]}")
        RUN0_ARGS="$RUN0_ARGS $home_arg"
    fi
    
    # Handle login shell
    if [[ "${OPTIONS[login_shell]}" == true ]]; then
        local shell_args
        shell_args=$(setup_login_shell "${OPTIONS[target_user]}")
        RUN0_ARGS="$RUN0_ARGS$shell_args"
    fi
}

# Main execution
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Execute run0 with our arguments
    if [[ -n "$COMMAND_ARGS" ]]; then
        if [[ "${OPTIONS[background_mode]}" == true ]]; then
            # Run in background - use nohup to properly detach
            nohup run0 $RUN0_ARGS $COMMAND_ARGS >/dev/null 2>&1 &
            exit 0
        else
            exec run0 $RUN0_ARGS $COMMAND_ARGS
        fi
    else
        if [[ "${OPTIONS[background_mode]}" == true ]]; then
            nohup run0 $RUN0_ARGS >/dev/null 2>&1 &
            exit 0
        else
            exec run0 $RUN0_ARGS
        fi
    fi
}

# Script entry point
main "$@"
