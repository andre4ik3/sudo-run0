#!/bin/bash
set -euo pipefail

# sudo-run0: A compatibility wrapper around systemd's run0 utility
# that can be used as a drop-in sudo replacement

# Version and constants
readonly VERSION="0.1.0"
readonly USAGE="usage: sudo -h | -K | -k | -V
usage: sudo -v [-nS] [-g group] [-u user]
usage: sudo -l [-nS] [-g group] [-u user] [command [arg ...]]
usage: sudo [-bEHnPS] [-D directory] [-g group] [-u user] [VAR=value] [-i | -s] [command [arg ...]]"

# Global variables for parsed options
declare -A OPTIONS=(
    [target_user]=""
    [target_group]=""
    [shell_target]=false
    [shell_own]=false
    [list_mode]=false
    [validate_mode]=false
    [preserve_env]=""
    [preserve_env_vars]=""
    [non_interactive]=false
    [background_mode]=false
    [reset_timestamp]=false
    [remove_timestamp]=false
    [working_directory]=""
    [preserve_groups]=false
    [ignore_env]=false
    [target_home]=false
)

declare -a RUN0_ARGS
declare -a COMMAND_ARGS

# Utility functions
die() {
    printf "sudo: %s\n" "$1" >&2
    exit 1
}

show_help() {
    cat << 'EOF'
sudo-run0 - execute a command as another user via systemd's run0 utility

usage: sudo -h | -K | -k | -V
usage: sudo -v [-nS] [-g group] [-u user]
usage: sudo -l [-nS] [-g group] [-u user] [command [arg ...]]
usage: sudo [-bEHnPS] [-D directory] [-g group] [-u user] [VAR=value] [-i | -s] [command [arg ...]]

Options:
  -b, --background              run command in the background
  -D, --chdir=directory         change the working directory before running command
  -E, --preserve-env            preserve user environment when running command
      --preserve-env=list       preserve specific environment variables
  -g, --group=group             run command as the specified group name or ID
  -H, --set-home                set HOME variable to target user's home dir
  -h, --help                    display help message and exit
  -i, --login                   run login shell as the target user; a command may also be specified
  -K, --remove-timestamp        remove timestamp file completely
  -k, --reset-timestamp         invalidate timestamp file
  -l, --list                    list user's privileges or check a specific command
  -n, --non-interactive         non-interactive mode, no prompts are used
  -P, --preserve-groups         preserve group vector instead of setting to target's
  -s, --shell                   run shell as the target user; a command may also be specified
  -u, --user=user               run command as specified user name or ID
  -V, --version                 display version information and exit
  -v, --validate                update user's timestamp without running a command
  --                            stop processing command line arguments
EOF
}

show_version() {
    run0_version="$(run0 --version 2>/dev/null | head -n 1 | cut -d' ' -f3 | sed 's/[()]//g')"
    echo "Sudo version 1.9.0" # fake version for compatibility
    echo "Sudo-run0 wrapper version $VERSION"
    echo "Systemd version $run0_version"
}

# Get shell for the target user or current user
get_shell() {
    local username shell
    if [[ "${OPTIONS[shell_target]}" == true ]]; then
        username="${OPTIONS[target_user]}"
    elif [[ "${OPTIONS[shell_own]}" == true ]]; then
        username="$USER"
        # for shell mode, allow SHELL to override the target shell
        if [[ -n "$SHELL" ]]; then
            echo "$SHELL"
            return
        fi
    fi
    # otherwise, get the shell of the target user
    shell=$(getent passwd "$username" 2>/dev/null | cut -d: -f7)
    case "$(basename "$shell")" in
        nologin|false|"") echo "/bin/sh" ;;
        *) echo "$shell" ;;
    esac
}

# Environment variable collection using run0's automatic value pickup
collect_env_vars() {
    local preserve_mode="$1"
    local specific_vars="$2"

    case "$preserve_mode" in
        "all")
            # Get all environment variables, excluding only the most problematic ones
            # Use run0's --setenv=NAME feature which automatically picks up values
            # Use -0 to handle newlines in values (null-terminated output)
            env -0 | while IFS= read -r -d '' line; do
                # Split on first = only
                local name="${line%%=*}"
                # Skip variables that would interfere with the new environment
                case "$name" in
                    # Skip setting caller's home if -H (set target user HOME) was specified
                    HOME) [[ "${OPTIONS[target_home]}" == true ]] && continue ;;
                    # Skip shell -- handled elsewhere
                    SHELL) continue ;;
                    # Skip shell-specific variables that should be reset
                    PWD|OLDPWD|SHLVL|_|PS1|PS2|PS3|PS4|USER|LOGNAME) continue ;;
                    # Skip sudo-specific variables
                    SUDO_*) continue ;;
                    # Skip dynamic linker variables for security
                    LD_*|NIX_LD*) continue ;;
                    # Skip other security-sensitive variables
                    IFS|ENV|BASH_ENV|KRB5*|KERBEROS*|LOCALDOMAIN|RES_OPTIONS) continue ;;
                    # Skip X11 and display variables that should be reset
                    XAUTHORITY|XAUTHORIZATION|DISPLAY|WINDOWPATH|WINDOWID) continue ;;
                    # NixOS-specific variables that should (probably) be reset
                    __NIXOS*|__HM*|NIX_PATH|NIX_PROFILES) continue ;;
                    # Skip if name is empty (shouldn't happen, but be safe)
                    "") continue ;;
                    # Pass everything else using run0's automatic value pickup
                    *) printf " --setenv=%s" "$name" ;;
                esac
            done
            ;;
        "specific")
            echo "$specific_vars" | tr ',' '\n' | while read -r var; do
                # Remove whitespace
                var=$(echo "$var" | tr -d ' \t')
                case "$var" in
                    # Dynamic linker variables are always excluded (security issue)
                    LD_*|NIX_LD*) continue ;;
                    # Other security-sensitive variables
                    IFS|ENV|BASH_ENV|KRB5*|KERBEROS*|LOCALDOMAIN|RES_OPTIONS) continue ;;
                    # Use parameter expansion instead of eval
                    *) [ -n "$var" ] && [ -n "${!var+x}" ] && printf " --setenv=%s" "$var" ;;
                esac
            done
            ;;
    esac

    # Always pass through caller's HOME unless -H (set target user HOME) is specified
    if [[ "${OPTIONS[target_home]}" != true ]] && [[ -n "$HOME" ]]; then
        printf " --setenv=HOME"
    fi
}

# Handle special sudo modes
handle_special_modes() {
    if [[ "${OPTIONS[list_mode]}" == true ]]; then
        echo "User $(whoami) may run the following commands on $(hostname):"
        echo "    (ALL) ALL"
        exit 0
    fi

    if [[ "${OPTIONS[validate_mode]}" == true ]]; then
        # Trigger authentication like real sudo -v
        run0 true >/dev/null 2>&1
        exit $?
    fi

    if [[ "${OPTIONS[reset_timestamp]}" == true ]] || [[ "${OPTIONS[remove_timestamp]}" == true ]]; then
        # Simulate timestamp reset by triggering a failing auth
        # This will effectively "reset" the polkit timestamp
        run0 --no-ask-password false >/dev/null 2>&1
        exit 0
    fi
}

# Determine final command to execute
# If set in a shell mode, sets COMMAND_ARGS to the shell and the command as one argument
# Otherwise, sets COMMAND_ARGS to the command and its arguments
build_command_args() {
    if [[ "${OPTIONS[shell_target]}" == true ]] || [[ "${OPTIONS[shell_own]}" == true ]]; then
        # Set the shell as the command to invoke, and optionally passthrough the command
        COMMAND_ARGS=("$(get_shell)")
        if [ $# -gt 0 ]; then
            COMMAND_ARGS+=("-c" "$*")
        fi
        return
    fi

    COMMAND_ARGS=("$@")
}

# Enhanced argument parsing using GNU getopt
parse_arguments() {
    # Define short and long options
    # + prefix means stop at first non-option (critical for sudo behavior)
    local short_opts="+u:g:D:isHEnbkKPlvhVIN"
    local long_opts="user:,group:,chdir:,login,shell,set-home,preserve-env::,non-interactive,background,reset-timestamp,remove-timestamp,preserve-groups,list,validate,help,version,ignore-env,no-update"

    # Parse arguments using getopt
    local parsed_args
    if ! parsed_args=$(getopt -o "$short_opts" -l "$long_opts" -n "sudo" -- "$@"); then
        echo "$USAGE" >&2
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
            -D|--chdir)
                OPTIONS[working_directory]="$2"
                shift 2
                ;;
            -i|--login)
                if [[ "${OPTIONS[shell_own]}" == true ]]; then
                    die "you may not specify both the -i and -s options"
                fi
                OPTIONS[shell_target]=true
                OPTIONS[target_home]=true
                shift
                ;;
            -s|--shell)
                if [[ "${OPTIONS[shell_target]}" == true ]]; then
                    die "you may not specify both the -i and -s options"
                fi
                OPTIONS[shell_own]=true
                shift
                ;;
            -H|--set-home) 
                OPTIONS[target_home]=true
                shift
                ;;
            -E|--preserve-env)
                if [[ "${OPTIONS[ignore_env]}" == true ]]; then
                    die "you may not specify both the -E and -I options"
                fi
                if [[ "$1" == "--preserve-env" && $# -gt 1 && "$2" != "--" ]]; then
                    # --preserve-env with a value (could be empty)
                    if [[ -z "$2" ]]; then
                        # Empty value - this is an error
                        printf "sudo: option '--preserve-env' requires a variable list\n" >&2
                        printf "%s\n" "$USAGE" >&2
                        exit 1
                    fi
                    OPTIONS[preserve_env]="specific"
                    OPTIONS[preserve_env_vars]="$2"
                    shift 2
                elif [[ "$1" == --preserve-env=* ]]; then
                    # --preserve-env=list format (shouldn't happen after getopt processing)
                    local env_list="${1#--preserve-env=}"
                    if [[ -z "$env_list" ]]; then
                        # Empty value - this is an error
                        printf "sudo: option '--preserve-env' requires a variable list\n" >&2
                        printf "%s\n" "$USAGE" >&2
                        exit 1
                    fi
                    OPTIONS[preserve_env]="specific"
                    OPTIONS[preserve_env_vars]="$env_list"
                    shift 1
                else
                    # -E format (preserve all) or --preserve-env without argument
                    OPTIONS[preserve_env]="all"
                    shift 1
                fi
                ;;
            -n|--non-interactive) OPTIONS[non_interactive]=true; shift ;;
            -b|--background) OPTIONS[background_mode]=true; shift ;;
            -k|--reset-timestamp) OPTIONS[reset_timestamp]=true; shift ;;
            -K|--remove-timestamp) OPTIONS[remove_timestamp]=true; shift ;;
            -P|--preserve-groups) OPTIONS[preserve_groups]=true; shift ;;
            -l|--list) OPTIONS[list_mode]=true; shift ;;
            -v|--validate) OPTIONS[validate_mode]=true; shift ;;
            -I|--ignore-env)
                # No-op since run0 clears environment by default
                if [[ -n "${OPTIONS[preserve_env]}" ]]; then
                    die "you may not specify both the -E and -I options"
                fi
                OPTIONS[ignore_env]=true
                shift
                ;;
            -N|--no-update)
                # No-op since run0 doesn't cache credentials
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

    # Handle special modes first (may exit early)
    handle_special_modes

    # Set default target user
    OPTIONS[target_user]="${OPTIONS[target_user]:-root}"

    # Show usage if no command is provided (default run0 behavior is to run a shell)
    if [ $# -eq 0 ] && \
       [[ "${OPTIONS[shell_target]}" != true ]] && \
       [[ "${OPTIONS[shell_own]}" != true ]]; then
        echo "$USAGE" >&2
        exit 1
    fi

    # Build run0 arguments and the command to execute
    build_run0_args
    build_command_args "$@"
}

# Build run0 arguments based on parsed options
build_run0_args() {
    RUN0_ARGS=("--shell-prompt-prefix=" "--background=" "--user=${OPTIONS[target_user]}")

    [[ -n "${OPTIONS[target_group]}" ]] && RUN0_ARGS+=("--group=${OPTIONS[target_group]}")
    [[ -n "${OPTIONS[working_directory]}" ]] && RUN0_ARGS+=("--chdir=${OPTIONS[working_directory]}")
    [[ "${OPTIONS[non_interactive]}" == true ]] && RUN0_ARGS+=("--no-ask-password")

    # Handle preserve groups (limited implementation)
    if [[ "${OPTIONS[preserve_groups]}" == true ]]; then
        local current_groups
        current_groups=$(id -G 2>/dev/null)
        [[ -n "$current_groups" ]] && RUN0_ARGS+=("--setenv=SUDO_GROUPS=$current_groups")
    fi

    # Handle environment variable preservation
    if [[ -n "${OPTIONS[preserve_env]}" ]]; then
        local env_args
        env_args=$(collect_env_vars "${OPTIONS[preserve_env]}" "${OPTIONS[preserve_env_vars]}")
        # Add environment arguments by parsing the string
        if [[ -n "$env_args" ]]; then
            eval "local env_array=($env_args)"
            RUN0_ARGS+=("${env_array[@]}")
        fi
    elif [[ "${OPTIONS[target_home]}" != true ]] && [[ -n "$HOME" ]]; then
        # If not preserving env but also not setting home, pass through HOME
        RUN0_ARGS+=("--setenv=HOME")
    fi

    # Handle shell mode
    if [[ "${OPTIONS[shell_target]}" == true ]] || [[ "${OPTIONS[shell_own]}" == true ]]; then
        RUN0_ARGS+=("--setenv=SHELL=$(get_shell)")
    fi
}

# Main execution
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Uncomment this to check the arguments run0 is called with
    # echo "sudo: executing run0 ${RUN0_ARGS[@]} ${COMMAND_ARGS[@]}" >&2

    # If you are really paranoid: require explicit confirmation (deny by default)
    # read -p "sudo: continue? [y/N] " -t 60 confirm
    # [[ "${confirm,,}" =~ ^y(es)?$ ]] || die "cancelled"

    # Execute run0 with our arguments
    if [[ "${OPTIONS[background_mode]}" == true ]]; then
        nohup run0 "${RUN0_ARGS[@]}" "${COMMAND_ARGS[@]}" >/dev/null 2>&1 &
        exit 0
    else
        exec run0 "${RUN0_ARGS[@]}" "${COMMAND_ARGS[@]}"
    fi
}

# Script entry point
main "$@"
