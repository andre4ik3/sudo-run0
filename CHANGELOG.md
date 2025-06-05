# Changelog

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
- **Environment variable parsing**: Now handles variables with `=` in values correctly using AWK
- **Code organization**: Split `parse_args()` into smaller, focused functions:
  - `handle_special_modes()` - Handles -l and -v options
  - `setup_login_shell()` - Configures login shell environment
  - `validate_shell()` - Validates and normalizes shell paths
  - `get_user_home()` - Dedicated function for home directory lookup
- **Argument parsing**: More concise and robust option handling
- **Help and version output**: Moved to dedicated functions for consistency

### Enhanced
- **Robustness**: Better handling of edge cases in environment variable processing
- **Maintainability**: Clear separation of concerns and improved code readability
- **Error messages**: More informative and sudo-compatible error reporting
- **Documentation**: Updated README with new requirements and improvements

### Technical Details
- Environment variables are now parsed using `awk` with proper field separation
- Eliminated potential issues with `IFS='='` parsing that could break on complex values
- Improved quote handling in specific environment variable preservation
- Better validation of user inputs and error handling throughout

## [1.1] - 2024

### Added
- Environment variable preservation with `-E` and `--preserve-env=list`
- Proper login shell handling using target user's shell
- NixOS compatibility for shell validation

### Improved
- Simplified user database access (getent only)
- Better shell validation using basename instead of full paths

## [1.0] - 2024

### Initial Release
- Basic sudo compatibility wrapper for run0
- Visual compatibility (disabled emoji and background colors)
- Common sudo options support (-u, -g, -i, -l, -v, -h, -V)
- Dual mode operation (sudo vs run0) 
