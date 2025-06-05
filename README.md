# sudo-run0: A sudo compatibility wrapper for systemd run0

This compatibility wrapper bridges the gap between traditional `sudo` and systemd's `run0`, enabling programs and scripts that expect sudo behavior to work seamlessly with run0's modern security model.

## Overview

**systemd run0** offers significant security improvements over traditional sudo through service isolation and polkit authentication, but introduces compatibility challenges for existing software. This wrapper addresses the most common compatibility issues while preserving run0's enhanced security model.

## Compatibility Analysis

### ✅ Issues This Wrapper Resolves

| **Compatibility Issue** | **sudo Behavior** | **run0 Default** | **Wrapper Solution** |
|---|---|---|---|
| **Visual Interface** | Clean, minimal output | Superhero emoji + colored background | Disables emoji and colors |
| **Environment Variables** | Preserves most variables by default | Provides clean environment | Implements `-E` and `--preserve-env` |
| **Login Shell (`-i`)** | Uses target user's shell | Uses invoking user's shell | Correctly uses target user's shell |
| **Option Compatibility** | Standard option set | Different option syntax | Maps common sudo options |
| **Error Messages** | Sudo-style error format | systemd-style errors | Provides sudo-compatible errors |
| **Help/Version Output** | Traditional sudo format | systemd format | Emulates sudo output style |

### ⚠️ Fundamental Differences That Remain

| **Aspect** | **sudo Behavior** | **run0 Behavior** | **Impact** |
|---|---|---|---|
| **Authentication** | Uses sudoers rules + password | Uses polkit + GUI/agent prompts | Different prompt appearance |
| **Configuration** | `/etc/sudoers` file | polkit rules in `/etc/polkit-1/` | No sudoers file compatibility |
| **Security Model** | SetUID binary, inherits context | Isolated systemd service | Better security, different process tree |
| **Logging** | Dedicated sudo logs | systemd journal | Different log location/format |
| **Advanced Options** | Full option set (`-H`, `-s`, `-c`, etc.) | Limited subset implemented | Some options not available |
| **Session Management** | sudo's own session handling | systemd service lifecycle | Different session behavior |

## Requirements

- **systemd 256+** (when run0 was introduced)
- **gawk** (GNU AWK) for robust environment variable parsing
- Standard POSIX utilities: `getent`, `cut`, `sed`, `tr`

## Installation

1. Copy `sudo-run0.sh` to your desired location (e.g., `/usr/local/bin/`)
2. Make it executable: `chmod +x sudo-run0.sh`
3. Create a symbolic link named `sudo`: `ln -s sudo-run0.sh sudo`
4. Ensure `gawk` is installed (most distributions include it by default)
5. Optionally, place it in your PATH to use system-wide

## Usage

### Basic Commands
```bash
# Basic privilege escalation
sudo whoami

# Run as different user
sudo -u username command

# Interactive login shell (uses target user's shell)
sudo -i

# Run shell as target user (simpler than -i)
sudo -s

# Set HOME directory
sudo -H command

# Environment variable preservation
sudo -E command                           # Preserve all safe variables
sudo --preserve-env=VAR1,VAR2 command    # Preserve specific variables

# Non-interactive mode (fails if authentication needed)
sudo -n command

# Background execution
sudo -b long-running-command

# Authentication management
sudo -l                                   # List privileges
sudo -v                                   # Validate/refresh authentication
sudo -k                                   # Reset authentication timestamp
sudo -K                                   # Remove authentication timestamp

# Execute commands via shell
sudo -c "complex command with pipes | and redirects"

# Change working directory before execution
sudo -D /var/log tail -f messages

# Preserve supplementary groups
sudo -P command
```

### Practical Examples
```bash
# Package management
sudo apt update

# File operations with environment
sudo -E make install

# User switching with login shell
sudo -u alice -i

# Development workflow
CFLAGS="-O2" sudo --preserve-env=CFLAGS make install

# Background system maintenance
sudo -b /usr/bin/system-cleanup

# Working directory change
sudo -D /var/www/html chown -R www-data:www-data .

# Complex shell commands
sudo -c "systemctl stop nginx && cp new-config /etc/nginx/ && systemctl start nginx"

# Non-interactive scripting
if sudo -n true 2>/dev/null; then
    sudo systemctl restart service
else
    echo "Authentication required"
fi
```

## Supported Options

| Option | Description | Compatibility |
|---|---|---|
| `-u, --user USER` | Run as specified user | ✅ Full |
| `-g, --group GROUP` | Run as specified group | ✅ Full |
| `-i, --login` | Login shell with target user's environment | ✅ Full |
| `-s, --shell` | Run shell as target user | ✅ Full |
| `-H, --set-home` | Set HOME to target user's home directory | ✅ Full |
| `-E, --preserve-env` | Preserve environment variables | ✅ Full (with safety filtering) |
| `--preserve-env=list` | Preserve specific variables | ✅ Full |
| `-n, --non-interactive` | Non-interactive mode (fail if auth needed) | ✅ Full |
| `-b, --background` | Run command in background | ✅ Full |
| `-k, --reset-timestamp` | Reset authentication timestamp | ✅ Full |
| `-K, --remove-timestamp` | Remove authentication timestamp | ✅ Full |
| `-c, --command=CMD` | Run command via shell | ✅ Full |
| `-D, --chdir=DIR` | Change working directory | ✅ Full |
| `-P, --preserve-groups` | Preserve supplementary groups | ⚠️ Limited (env var only) |
| `-l, --list` | List privileges | ⚠️ Simplified (shows generic output) |
| `-v, --validate` | Validate/refresh authentication | ✅ Full |
| `-h, --help` | Show help | ✅ Full |
| `-V, --version` | Show version | ✅ Full |

### Not Yet Implemented

| Option | Description | Implementation Difficulty |
|---|---|---|
| `-S, --stdin` | Read password from stdin | 🔴 **Impossible** (polkit limitation) |
| `-A, --askpass` | Use askpass program | 🔴 **Impossible** (polkit limitation) |
| `-r, --role` | SELinux role | 🔴 **Hard** (requires SELinux support in run0) |
| `-t, --type` | SELinux type | 🔴 **Hard** (requires SELinux support in run0) |
| `-e, --edit` | Edit files (sudoedit) | 🟡 **Hard** (complex implementation needed) |
| `-p, --prompt` | Custom password prompt | 🟡 **Hard** (limited polkit control) |

## Migration Guide

### For Scripts and Programs
Most scripts using basic sudo functionality will work without modification:
```bash
# These work identically
sudo systemctl restart nginx
sudo -u www-data touch /var/www/file
sudo -i
```

### For Advanced Use Cases
Some advanced sudo features require adaptation:
```bash
# Not available - use alternative approaches
sudo -S          # Use GUI authentication instead
sudo -A          # Use system's polkit agent instead
sudo -e file     # Use regular editor with sudo: sudo vim file
```

### Configuration Migration
- **sudoers rules** → **polkit rules** (manual conversion required)
- **sudo logs** → **systemd journal** (`journalctl -t run0`)
- **Authentication config** → **polkit configuration**

## Architecture

### Security Model
- **Isolation**: Each command runs in a fresh systemd service
- **Authentication**: Leverages polkit's robust permission framework  
- **No SetUID**: Eliminates traditional sudo security risks
- **Audit Trail**: Full logging through systemd journal

### Implementation Details
- **Environment Parsing**: GNU AWK handles complex variable parsing
- **Shell Detection**: Uses `getent` for robust user database queries
- **Error Handling**: Comprehensive validation with sudo-compatible messages
- **Modular Design**: 11 focused functions for maintainability

## Troubleshooting

### Common Issues
1. **Different authentication prompts**: Expected with polkit vs sudo
2. **Missing sudoers rules**: Convert to polkit rules as needed
3. **Environment differences**: Use `-E` or `--preserve-env` as needed
4. **Script compatibility**: Most basic usage works unchanged

### Environment Variable Filtering
For safety, these variable types are filtered with `-E`:
- System variables (PWD, SHLVL, PS1-4)
- Complex path variables (*_PATH, *_DIRS) 
- Variables with shell metacharacters
- Variables longer than 200 characters

## Development

### Version History
- **v1.3**: Enhanced error handling and input validation
- **v1.2**: Robust environment parsing with AWK, modular architecture  
- **v1.1**: Environment preservation, proper login shell handling
- **v1.0**: Basic sudo compatibility wrapper

### Contributing
1. Add option parsing in `parse_arguments()`
2. Map to appropriate run0 arguments
3. Update help text and documentation
4. Add comprehensive tests

## License

Released into the public domain. Modify and distribute freely. 
