#!/bin/sh

# sudo-run0: A compatibility wrapper around systemd's run0 utility
# that can be used as a drop-in sudo replacement

# Get the target user's shell from /etc/passwd
get_user_shell() {
    local username="$1"
    if [ -z "$username" ]; then
        username="root"
    fi
    
    # Use getent to get user information
    getent passwd "$username" 2>/dev/null | cut -d: -f7
}

# Collect environment variables for preservation
collect_env_vars() {
    local preserve_mode="$1"
    local specific_vars="$2"
    
    case "$preserve_mode" in
        "all")
            # Preserve environment variables, but be selective to avoid issues
            env | while IFS='=' read -r key value; do
                # Skip empty lines and variables that might cause issues
                [ -z "$key" ] && continue
                case "$key" in
                    # Skip variables that run0/systemd manages
                    PWD|OLDPWD|SHLVL|_|PS1|PS2|PS3|PS4) continue ;;
                    # Skip sudo-specific variables
                    SUDO_*) continue ;;
                    # Skip very complex variables that cause command line issues
                    LS_COLORS|FZF_DEFAULT_OPTS|NIX_PROFILES|*_PATH|*_DIRS|INFOPATH|XDG_*) continue ;;
                    # Skip other potentially problematic variables
                    MANPATH|PKG_CONFIG_PATH|FONTCONFIG_FILE|GIO_EXTRA_MODULES) continue ;;
                    *) 
                        # Only include simple, safe variables
                        if [ -n "$value" ] && [ ${#value} -lt 200 ]; then
                            case "$value" in
                                # Skip values with problematic characters
                                *\"*|*\'*|*\$*|*\`*|*\\*|*\;*|*\|*|*\&*|*\(*|*\)*) continue ;;
                                # Skip values with spaces (they need special handling)
                                *\ *) continue ;;
                                *) printf ' --setenv=%s=%s' "$key" "$value" ;;
                            esac
                        fi
                        ;;
                esac
            done
            ;;
        "specific")
            # Preserve only specified variables
            for var in $(echo "$specific_vars" | tr ',' ' '); do
                # Remove any whitespace
                var=$(echo "$var" | tr -d ' \t')
                if [ -n "$var" ]; then
                    value=$(eval "echo \"\$$var\"" 2>/dev/null)
                    if [ -n "$value" ]; then
                        # For specific variables, we'll handle them more carefully
                        # Escape quotes and backslashes in the value
                        escaped_value=$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
                        printf ' --setenv=%s="%s"' "$var" "$escaped_value"
                    fi
                fi
            done
            ;;
    esac
}

# Parse arguments and build run0 command
parse_args() {
    local run0_args=""
    local target_user=""
    local target_group=""
    local login_shell=false
    local list_mode=false
    local validate_mode=false
    local preserve_env=""
    local preserve_env_vars=""
    
    # Always disable visual changes for sudo compatibility
    run0_args="--shell-prompt-prefix= --background="
    
    # Parse command line arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                echo "usage: sudo [-u user] [-g group] [-i] [-E] [--preserve-env[=list]] [-l] [-v] [-h] [-V] command [args...]"
                echo ""
                echo "Options:"
                echo "  -u, --user USER               run command as specified user"
                echo "  -g, --group GROUP             run command as specified group"
                echo "  -i, --login                   run shell as target user's login shell"
                echo "  -E, --preserve-env            preserve all environment variables"
                echo "      --preserve-env=list       preserve specific environment variables (comma-separated)"
                echo "  -l, --list                    list user's privileges"
                echo "  -v, --validate                update user's timestamp"
                echo "  -h, --help                    display this help message"
                echo "  -V, --version                 display version information"
                exit 0
                ;;
            -V|--version)
                echo "sudo-run0 compatibility wrapper 1.1"
                echo "This is a wrapper around systemd run0 for sudo compatibility"
                echo "Underlying run0 version:"
                run0 --version 2>/dev/null || echo "run0 version unavailable"
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
                if [ -n "$2" ]; then
                    target_user="$2"
                    shift 2
                else
                    echo "sudo: option requires an argument -- u" >&2
                    exit 1
                fi
                ;;
            -u*)
                target_user="${1#-u}"
                shift
                ;;
            -g|--group)
                if [ -n "$2" ]; then
                    target_group="$2"
                    shift 2
                else
                    echo "sudo: option requires an argument -- g" >&2
                    exit 1
                fi
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
                echo "usage: sudo [-u user] [-g group] [-i] [-E] [--preserve-env[=list]] [-l] [-v] [-h] [-V] command [args...]" >&2
                exit 1
                ;;
            *)
                # Non-option argument - this and everything after goes to the command
                break
                ;;
        esac
    done
    
    # Handle special modes
    if [ "$list_mode" = true ]; then
        echo "User $(whoami) may run the following commands:"
        echo "    (ALL) ALL"
        exit 0
    fi
    
    if [ "$validate_mode" = true ]; then
        # Just trigger authentication like real sudo -v
        run0 /bin/true >/dev/null 2>&1
        exit $?
    fi
    
    # Set default target user if not specified
    if [ -z "$target_user" ]; then
        target_user="root"
    fi
    
    # Add user/group arguments
    run0_args="$run0_args --user=$target_user"
    if [ -n "$target_group" ]; then
        run0_args="$run0_args --group=$target_group"
    fi
    
    # Handle environment variable preservation
    if [ -n "$preserve_env" ]; then
        env_args=$(collect_env_vars "$preserve_env" "$preserve_env_vars")
        run0_args="$run0_args$env_args"
    fi
    
    # Handle login shell
    if [ "$login_shell" = true ]; then
        # Get the target user's shell
        target_shell=$(get_user_shell "$target_user")
        
        # Check if shell is invalid by examining the basename
        case "$(basename "$target_shell")" in
            nologin|false|"")
                target_shell="/bin/sh"
                ;;
        esac
        
        # Set up login shell environment
        run0_args="$run0_args --setenv=SHELL=$target_shell"
        
        # Set appropriate HOME directory
        if [ "$target_user" = "root" ]; then
            run0_args="$run0_args --setenv=HOME=/root"
        else
            # Get user's home directory
            target_home=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)
            if [ -n "$target_home" ]; then
                run0_args="$run0_args --setenv=HOME=$target_home"
            fi
        fi
        
        # If no command specified with -i, start the target user's shell
        if [ $# -eq 0 ]; then
            set -- "$target_shell"
        fi
    fi
    
    # Export the parsed arguments
    RUN0_ARGS="$run0_args"
    COMMAND_ARGS="$*"
}

# Main execution
main() {
    # Parse arguments
    parse_args "$@"
    
    # Execute run0 with our arguments
    if [ -n "$COMMAND_ARGS" ]; then
        exec run0 $RUN0_ARGS $COMMAND_ARGS
    else
        # No command specified, start interactive shell
        exec run0 $RUN0_ARGS
    fi
}

# Execute main function with all arguments
main "$@"
