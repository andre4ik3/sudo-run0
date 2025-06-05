# sudo-run0: A sudo compatibility wrapper for systemd run0

This is a compatibility wrapper around systemd's `run0` utility that can be used as a drop-in replacement for `sudo` in programs and scripts that call the sudo binary.

## Features

- **Visual Compatibility**: When called as `sudo`, disables run0's superhero emoji and background color changes that would be inappropriate for sudo compatibility
- **Argument Compatibility**: Maps common sudo options to their run0 equivalents
- **Dual Mode**: Works both as a sudo replacement and as a regular run0 wrapper
- **Minimal Dependencies**: Written in POSIX shell for maximum portability

## Installation

1. Copy `sudo-run0.sh` to your desired location (e.g., `/usr/local/bin/`)
2. Make it executable: `chmod +x sudo-run0.sh`
3. Create a symbolic link named `sudo`: `ln -s sudo-run0.sh sudo`
4. Optionally, place it in your PATH to use system-wide

## Usage

### As sudo replacement
```bash
# Basic usage
./sudo whoami

# Run as different user
./sudo -u username command

# Run as different group  
./sudo -g groupname command

# Interactive login shell
./sudo -i

# List privileges
./sudo -l

# Validate/refresh authentication
./sudo -v

# Help
./sudo --help

# Version information
./sudo --version
```

### As run0 wrapper
```bash
# All run0 options are passed through
./sudo-run0.sh --user=username command
./sudo-run0.sh --property=CPUQuota=50% command
```

## Supported sudo Options

When called as `sudo`, the following options are supported:

- `-u, --user USER`: Run command as specified user
- `-g, --group GROUP`: Run command as specified group  
- `-i, --login`: Run shell as login shell
- `-l, --list`: List user's privileges (simplified output)
- `-v, --validate`: Update user's timestamp (triggers authentication)
- `-h, --help`: Display help message
- `-V, --version`: Display version information

## Behavior Differences

### When called as `sudo`:
- Superhero emoji prompt prefix is disabled (`--shell-prompt-prefix=""`)
- Background color changes are disabled (`--background=""`)
- Only sudo-compatible options are accepted
- Error messages match sudo format
- Help and version output is sudo-style

### When called as the original name (e.g., `sudo-run0.sh`):
- All run0 options are passed through unchanged
- Normal run0 visual behavior is preserved
- Full run0 functionality is available

## Examples

```bash
# Install system package (as sudo)
./sudo apt update

# Edit system file (as sudo)
./sudo -u root nano /etc/hosts

# Switch to user account (as sudo)
./sudo -u alice -i

# Run with run0 features (direct call)
./sudo-run0.sh --property=MemoryMax=1G --user=alice command
```

## Implementation Notes

- Built for systemd environments with run0 available
- Uses polkit for authentication (like run0)
- Maintains run0's security model with fresh service isolation
- No SetUID/SetGID required (inherits run0's design)
- Compatible with systemd 256+ (when run0 was introduced)

## Limitations

- Not all sudo options are implemented (only the most common ones)
- Some advanced sudo features like sudoers rules are simplified
- Requires systemd and run0 to be available
- Authentication prompts may look different (polkit vs sudo)

## Contributing

This wrapper is designed to be extensible. To add support for additional sudo options:

1. Add the option parsing in the `parse_args()` function
2. Map it to appropriate run0 arguments
3. Update the help text and documentation

## License

This project is released into the public domain. Feel free to modify and distribute as needed. 
