# sudo-run0: A sudo compatibility wrapper for systemd run0

This is a compatibility wrapper around systemd's `run0` utility that can be used as a drop-in replacement for `sudo` in programs and scripts that call the sudo binary.

## Features

- **Visual Compatibility**: Disables run0's superhero emoji and background color changes that would be inappropriate for sudo compatibility
- **Environment Variable Preservation**: Supports `-E` and `--preserve-env` for maintaining environment variables across privilege escalation
- **Proper Login Shell Handling**: The `-i` option correctly uses the target user's shell (not the invoking user's shell)
- **Argument Compatibility**: Maps common sudo options to their run0 equivalents
- **Minimal Dependencies**: Written in POSIX shell for maximum portability
- **Security**: Inherits run0's security model with service isolation and polkit authentication

## Installation

1. Copy `sudo-run0.sh` to your desired location (e.g., `/usr/local/bin/`)
2. Make it executable: `chmod +x sudo-run0.sh`
3. Create a symbolic link named `sudo`: `ln -s sudo-run0.sh sudo`
4. Optionally, place it in your PATH to use system-wide

## Usage

### Basic Usage
```bash
# Basic privilege escalation
sudo whoami

# Run as different user
sudo -u username command

# Run as different group  
sudo -g groupname command

# Interactive login shell (uses target user's shell and home)
sudo -i

# Preserve all environment variables
sudo -E command

# Preserve specific environment variables
sudo --preserve-env=PATH,HOME command

# List privileges
sudo -l

# Validate/refresh authentication
sudo -v

# Help and version
sudo --help
sudo --version
```

### Environment Variable Examples
```bash
# Preserve your current PATH when running as root
sudo -E which your-command

# Preserve specific variables for a build process
CFLAGS="-O2" CXXFLAGS="-O2" sudo --preserve-env=CFLAGS,CXXFLAGS make install

# Use login shell with clean environment
sudo -i  # Gets root's shell and home directory
```

## Supported sudo Options

- `-u, --user USER`: Run command as specified user
- `-g, --group GROUP`: Run command as specified group  
- `-i, --login`: Run shell as target user's login shell
- `-E, --preserve-env`: Preserve all environment variables (filtered for safety)
- `--preserve-env=list`: Preserve specific environment variables (comma-separated)
- `-l, --list`: List user's privileges (simplified output)
- `-v, --validate`: Update user's timestamp (triggers authentication)
- `-h, --help`: Display help message
- `-V, --version`: Display version information

## Key Compatibility Improvements

### Environment Variable Handling
Unlike standard `run0` which provides a clean environment, this wrapper:
- Supports sudo-style environment preservation with `-E`
- Allows selective variable preservation with `--preserve-env=list`
- Filters out problematic variables that could break the command line
- Properly handles variables with special characters

### Login Shell Behavior
Fixes a key difference between `run0` and `sudo`:
- **run0 default**: Uses invoking user's shell (e.g., if your shell is zsh, root gets zsh)
- **sudo -i behavior**: Uses target user's shell (e.g., if root's shell is bash, you get bash)
- **This wrapper**: Correctly implements sudo's behavior for `-i`

### Visual Changes
- Disables superhero emoji prompt prefix
- Disables background color changes
- Provides sudo-style help and error messages

## Examples

```bash
# Traditional sudo usage
sudo apt update
sudo -u alice cat /home/alice/file.txt

# Environment preservation
export BUILD_TYPE=release
sudo -E make install  # Preserves BUILD_TYPE

# Selective environment preservation
sudo --preserve-env=HOME,USER,LANG command

# Login shell (gets target user's shell and environment)
sudo -i                    # Interactive root shell
sudo -u alice -i           # Interactive shell as alice

# Combined options
sudo -u bob -E --preserve-env=DISPLAY xterm  # Run xterm as bob with display
```

## Implementation Notes

- **Security Model**: Inherits run0's service isolation and polkit authentication
- **No SetUID Required**: Uses systemd's privilege escalation mechanism
- **Environment Filtering**: Automatically filters out problematic variables to prevent command line corruption
- **Shell Detection**: Uses `getent` to determine target user's shell with fallback logic
- **NixOS Compatibility**: Handles non-standard binary paths by checking basenames instead of full paths
- **Compatibility**: Works with systemd 256+ (when run0 was introduced)

## Limitations

- **Environment Filtering**: Some complex environment variables are filtered out for stability
- **Command Line Length**: Very long environment values are skipped to prevent issues
- **systemd Dependency**: Requires systemd with run0 available
- **Authentication**: Uses polkit prompts which may look different from traditional sudo

## Technical Details

### Environment Variable Filtering
For safety and compatibility, the following variables are filtered out when using `-E`:
- System variables managed by systemd/run0 (PWD, SHLVL, etc.)
- Complex path variables that can break command lines (PATH, LD_LIBRARY_PATH, etc.)
- Variables with special characters that could cause shell injection
- Very long variables (>200 characters) that could exceed command line limits

### Login Shell Implementation
The `-i` option:
1. Looks up the target user's shell from the system user database using `getent`
2. Validates the shell by checking the basename (works on both traditional Unix and NixOS)
3. Sets `SHELL` environment variable to the target user's shell
4. Sets `HOME` to the target user's home directory
5. Falls back to `/bin/sh` if target user has invalid shell (nologin, false, etc.)

## Contributing

This wrapper is designed to be extensible. To add support for additional sudo options:

1. Add the option parsing in the `parse_args()` function
2. Map it to appropriate run0 arguments  
3. Update the help text and documentation
4. Test thoroughly with various edge cases

## License

This project is released into the public domain. Feel free to modify and distribute as needed. 
