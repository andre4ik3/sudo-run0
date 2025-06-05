# Changelog

## [1.6] - 2024

### Bug Fixes
- **Fixed `-c, --command` option**: Resolved issue where shell commands weren't executing properly due to quoting problems
- **Shell command execution**: Now properly handles complex commands with pipes, redirects, and special characters
- **Direct execution**: Shell commands (-c) now execute directly without intermediate processing to avoid quoting issues

### Code Quality Improvements
- **Eliminated duplicate logic**: Consolidated shell detection and HOME directory setting into reusable functions
- **Refactored argument processing**: Created `get_target_shell()` and `set_target_home()` helper functions
- **Simplified command determination**: Streamlined the logic for determining final commands to execute
- **Reduced code repetition**: Shell and HOME directory logic now reused across `-i`, `-s`, `-H`, and `-c` options

### Enhanced Functions
- **`get_target_shell()`**: Consolidated function for shell detection and validation
- **`set_target_home()`**: Centralized HOME directory determination for consistency
- **`determine_final_command()`**: Unified command preparation logic (except for -c special case)
- **`setup_login_shell()`**: Refactored to use new helper functions

### Technical Improvements
- **Better separation of concerns**: Each function now has a single, clear responsibility
- **Improved maintainability**: Reduced code duplication makes future changes easier
- **Enhanced reliability**: Direct execution of shell commands eliminates quoting edge cases
- **Consistent behavior**: All shell-related options now use the same underlying functions

### Testing Results
- ✅ Complex shell commands with pipes and redirects work correctly
- ✅ Option combinations (e.g., `-H -c`) function properly  
- ✅ All existing functionality preserved during refactoring
- ✅ Shell detection works correctly across different Unix systems

## [1.5] - 2024

### Major Feature Expansion
- **9 New sudo options**: Significantly expanded compatibility with real sudo
- **Easy options implemented**: `-s`, `-H`, `-n`, `-b`, `-k`, `-K` with full functionality
- **Medium complexity options**: `-c`, `-D`, `-P` with robust implementations

### Added Options
- **`-s, --shell`**: Run shell as target user (simpler alternative to `-i`)
- **`-H, --set-home`**: Set HOME variable to target user's home directory
- **`-n, --non-interactive`**: Non-interactive mode using run0's `--no-ask-password`
- **`-b, --background`**: Run command in background using `nohup` for proper detachment
- **`-k, --reset-timestamp`**: Reset authentication timestamp (simulated via failed auth)
- **`-K, --remove-timestamp`**: Remove authentication timestamp (simulated via failed auth)
- **`-c, --command=CMD`**: Execute command via target user's shell with proper argument handling
- **`-D, --chdir=DIR`**: Change working directory before command execution with validation
- **`-P, --preserve-groups`**: Preserve supplementary groups (limited implementation via env vars)

### Improved
- **Option coverage**: Now supports 18 out of ~25 common sudo options (72% compatibility)
- **Argument parsing**: Enhanced parsing logic with proper error handling for new options
- **Directory validation**: Added existence checks for `-D` option with appropriate error messages
- **Shell command execution**: Proper shell selection and command escaping for `-c` option

### Enhanced
- **Background execution**: Uses `nohup` for proper process detachment in `-b` mode
- **Timestamp simulation**: Clever use of run0's authentication to simulate sudo's timestamp behavior
- **Home directory logic**: Consistent HOME setting between `-H`, `-i`, and `-s` options
- **Compatibility messaging**: Clear documentation of implemented vs. impossible features

### Technical Details
- Shell command (`-c`) properly ignores remaining arguments like real sudo
- Working directory (`-D`) validates accessibility before passing to run0
- Background mode (`-b`) properly detaches processes with stdout/stderr redirection
- Group preservation (`-P`) stores current groups in environment variable for reference
- All new options maintain compatibility with existing option combinations

## [1.4] - 2024

### Improved
- **Error handling**: Enhanced invalid argument and missing argument error reporting
- **Error messages**: More sudo-like error message format and consistent usage display
- **Input validation**: Added validation for empty `--preserve-env=` arguments
- **User experience**: Better error messages with proper formatting (no literal \n)

### Added
- **Comprehensive error tests**: Extended test suite to validate error handling scenarios
- **Usage display**: Dedicated `show_usage()` function for consistent error output

### Technical Details
- Replaced `die()` function usage for argument errors with specific error handling
- Added proper validation for `--preserve-env=` with empty variable lists
- Improved error message formatting using `printf` instead of `echo` for consistency
- Enhanced test coverage to include all error scenarios

## [1.3] - 2024

### Improved
- **Error handling**: Enhanced invalid argument and missing argument error reporting
- **Error messages**: More sudo-like error message format and consistent usage display
- **Input validation**: Added validation for empty `--preserve-env=` arguments
- **User experience**: Better error messages with proper formatting (no literal \n)

### Added
- **Comprehensive error tests**: Extended test suite to validate error handling scenarios
- **Usage display**: Dedicated `show_usage()` function for consistent error output

### Technical Details
- Replaced `die()` function usage for argument errors with specific error handling
- Added proper validation for `--preserve-env=` with empty variable lists
- Improved error message formatting using `printf` instead of `echo` for consistency
- Enhanced test coverage to include all error scenarios

## [1.2] - 2024

### Added
- **gawk dependency**: Introduced GNU AWK for robust environment variable parsing
- **Modular function design**: Split large functions into focused, maintainable modules
- **Comprehensive error handling**: Added `die()` function and improved error messages
- **Constants and versioning**: Added version constants and proper script organization

### Improved
- **Environment variable parsing**: Now handles variables with `
