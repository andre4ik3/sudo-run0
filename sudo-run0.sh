#!/bin/sh

# sudo-run0: A compatibility wrapper around systemd's run0 utility
# that can be used as a drop-in sudo replacement

# Determine how this script was invoked
SCRIPT_NAME=$(basename "$0")

# Check if we're being called as 'sudo'
is_sudo_mode() {
    case "$SCRIPT_NAME" in
        sudo|sudo.*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Parse arguments and build run0 command
parse_args() {
    local run0_args=""
    local user_args=""
    local target_user=""
    local target_group=""
    local login_shell=false
    local list_mode=false
    local validate_mode=false
    
    # If called as sudo, disable visual changes that are inappropriate
    if is_sudo_mode; then
        # Disable the superhero emoji prompt prefix
        run0_args="$run0_args --shell-prompt-prefix="
        # Disable background color changes
        run0_args="$run0_args --background="
    fi
    
    # Parse command line arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                if is_sudo_mode; then
                    echo "usage: sudo [-u user] [-g group] [-i] [-l] [-v] [-h] [-V] command [args...]"
                    echo ""
                    echo "Options:"
                    echo "  -u, --user USER    run command as specified user"
                    echo "  -g, --group GROUP  run command as specified group"
                    echo "  -i, --login        run shell as login shell"
                    echo "  -l, --list         list user's privileges"
                    echo "  -v, --validate     update user's timestamp"
                    echo "  -h, --help         display this help message"
                    echo "  -V, --version      display version information"
                else
                    # Pass through to run0
                    user_args="$user_args $1"
                    shift
                fi
                exit 0
                ;;
            -V|--version)
                if is_sudo_mode; then
                    echo "sudo-run0 compatibility wrapper 1.0"
                    echo "This is a wrapper around systemd run0 for sudo compatibility"
                    echo "Underlying run0 version:"
                    run0 --version 2>/dev/null || echo "run0 version unavailable"
                else
                    # Pass through to run0
                    user_args="$user_args $1"
                    shift
                fi
                exit 0
                ;;
            -l|--list)
                if is_sudo_mode; then
                    list_mode=true
                    shift
                else
                    user_args="$user_args $1"
                    shift
                fi
                ;;
            -v|--validate)
                if is_sudo_mode; then
                    validate_mode=true
                    shift
                else
                    user_args="$user_args $1"
                    shift
                fi
                ;;
            -u|--user)
                if [ -n "$2" ]; then
                    target_user="$2"
                    shift 2
                else
                    echo "Error: -u requires an argument" >&2
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
                    echo "Error: -g requires an argument" >&2
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
                # Unknown option - pass through to run0 if not in sudo mode
                if is_sudo_mode; then
                    echo "sudo: invalid option -- '${1#-}'" >&2
                    echo "usage: sudo [-u user] [-g group] [-i] [-l] [-v] [-h] [-V] command [args...]" >&2
                    exit 1
                else
                    user_args="$user_args $1"
                    shift
                fi
                ;;
            *)
                # Non-option argument - this and everything after goes to the command
                break
                ;;
        esac
    done
    
    # Handle special modes for sudo compatibility
    if is_sudo_mode; then
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
    fi
    
    # Add user/group if specified
    if [ -n "$target_user" ]; then
        run0_args="$run0_args --user=$target_user"
    fi
    if [ -n "$target_group" ]; then
        run0_args="$run0_args --group=$target_group"
    fi
    
    # Handle login shell
    if [ "$login_shell" = true ]; then
        if [ $# -eq 0 ]; then
            # No command specified with -i, start a login shell
            set -- "${SHELL:-/bin/sh}"
        fi
        # Set environment to make it more like a login shell
        run0_args="$run0_args --setenv=HOME=/root"
    fi
    
    # Export the parsed arguments
    RUN0_ARGS="$run0_args$user_args"
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
