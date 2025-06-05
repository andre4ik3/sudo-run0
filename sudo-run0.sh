#!/bin/sh

# sudo-run0: A compatibility wrapper around systemd's run0 utility
# that can be used as a drop-in sudo replacement

# Version and constants
readonly VERSION="1.2"
readonly USAGE="usage: sudo [-u user] [-g group] [-i] [-E] [--preserve-env[=list]] [-l] [-v] [-h] [-V] command [args...]"

# Global variables for parsed options
RUN0_ARGS=""
COMMAND_ARGS=""

# Utility functions
die() {
    echo "sudo: $*" >&2
    exit 1
}

show_help() {
    cat << 'EOF'
usage: sudo [-u user] [-g group] [-i] [-E] [--preserve-env[=list]] [-l] [-v] [-h] [-V] command [args...]

Options:
  -u, --user USER               run command as specified user
  -g, --group GROUP             run command as specified group
  -i, --login                   run shell as target user's login shell
  -E, --preserve-env            preserve all environment variables
      --preserve-env=list       preserve specific environment variables (comma-separated)
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

# Environment variable collection using awk for robust parsing
collect_env_vars() {
    local preserve_mode="$1"
    local specific_vars="$2"
    
    case "$preserve_mode" in
        "all")
            # Use awk for robust environment variable parsing
            env | awk -F= '
            # Skip problematic variables that could break the command line
            /^(PWD|OLDPWD|SHLVL|_|PS[1-4])=/ { next }
            /^SUDO_/ { next }
            /^(LS_COLORS|FZF_DEFAULT_OPTS|NIX_PROFILES)=/ { next }
            /_(PATH|DIRS)=/ { next }
            /^(INFOPATH|MANPATH|PKG_CONFIG_PATH|FONTCONFIG_FILE|GIO_EXTRA_MODULES)=/ { next }
            /^XDG_/ { next }
            
            # For remaining variables, reconstruct properly
            {
                # Find first = to split key and value correctly
                eq_pos = index($0, "=")
                if (eq_pos > 0) {
                    key = substr($0, 1, eq_pos - 1)
                    value = substr($0, eq_pos + 1)
                    
                    # Skip if key is empty or value is too long
                    if (key == "" || length(value) > 200) next
                    
                    # Skip values with problematic characters for the "all" mode
                    if (match(value, /["'"'"'$`\\;|&()]/) || match(value, / /)) next
                    
                    printf " --setenv=%s=%s", key, value
                }
            }'
            ;;
        "specific")
            # For specific variables, handle them more carefully with proper quoting
            echo "$specific_vars" | tr ',' '\n' | while read -r var; do
                # Remove whitespace
                var=$(echo "$var" | tr -d ' \t')
                if [ -n "$var" ]; then
                    value=$(eval "printf '%s' \"\$$var\"" 2>/dev/null)
                    if [ -n "$value" ]; then
                        # Escape for shell safety
                        escaped_value=$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
                        printf ' --setenv=%s="%s"' "$var" "$escaped_value"
                    fi
                fi
            done
            ;;
    esac
}

# Handle special sudo modes
handle_special_modes() {
    local list_mode="$1"
    local validate_mode="$2"
    
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
}

# Configure login shell environment
setup_login_shell() {
    local target_user="$1"
    local shell_args=""
    
    # Get and validate target user's shell
    local target_shell
    target_shell=$(get_user_shell "$target_user")
    target_shell=$(validate_shell "$target_shell")
    
    shell_args="$shell_args --setenv=SHELL=$target_shell"
    
    # Set appropriate HOME directory
    if [ "$target_user" = "root" ]; then
        shell_args="$shell_args --setenv=HOME=/root"
    else
        local target_home
        target_home=$(get_user_home "$target_user")
        if [ -n "$target_home" ]; then
            shell_args="$shell_args --setenv=HOME=$target_home"
        fi
    fi
    
    echo "$shell_args"
}

# Parse command line arguments
parse_arguments() {
    local target_user=""
    local target_group=""
    local login_shell=false
    local list_mode=false
    local validate_mode=false
    local preserve_env=""
    local preserve_env_vars=""
    
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
            -E|--preserve-env)
                preserve_env="all"
                shift
                ;;
            --preserve-env=*)
                preserve_env="specific"
                preserve_env_vars="${1#--preserve-env=}"
                shift
                ;;
            -u|--user)
                [ -z "$2" ] && die "option requires an argument -- u"
                target_user="$2"
                shift 2
                ;;
            -u*)
                target_user="${1#-u}"
                shift
                ;;
            -g|--group)
                [ -z "$2" ] && die "option requires an argument -- g"
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
                die "invalid option -- '${1#-}'\n$USAGE"
                ;;
            *)
                # Non-option argument
                break
                ;;
        esac
    done
    
    # Handle special modes first
    handle_special_modes "$list_mode" "$validate_mode"
    
    # Set default target user
    target_user="${target_user:-root}"
    
    # Build run0 arguments
    RUN0_ARGS="$RUN0_ARGS --user=$target_user"
    [ -n "$target_group" ] && RUN0_ARGS="$RUN0_ARGS --group=$target_group"
    
    # Handle environment variable preservation
    if [ -n "$preserve_env" ]; then
        local env_args
        env_args=$(collect_env_vars "$preserve_env" "$preserve_env_vars")
        RUN0_ARGS="$RUN0_ARGS$env_args"
    fi
    
    # Handle login shell
    if [ "$login_shell" = true ]; then
        local shell_args
        shell_args=$(setup_login_shell "$target_user")
        RUN0_ARGS="$RUN0_ARGS$shell_args"
        
        # If no command specified with -i, start the target user's shell
        if [ $# -eq 0 ]; then
            local target_shell
            target_shell=$(get_user_shell "$target_user")
            target_shell=$(validate_shell "$target_shell")
            set -- "$target_shell"
        fi
    fi
    
    # Set remaining command arguments
    COMMAND_ARGS="$*"
}

# Main execution
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Execute run0 with our arguments
    if [ -n "$COMMAND_ARGS" ]; then
        exec run0 $RUN0_ARGS $COMMAND_ARGS
    else
        exec run0 $RUN0_ARGS
    fi
}

# Script entry point
main "$@"
