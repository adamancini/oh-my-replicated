# Test Suite

This directory contains a comprehensive test suite for both Oh My Replicated plugins:

- `replicated-gcommands.plugin.zsh` (GCP instance management)
- `replicated-awscommands.plugin.zsh` (AWS EC2 instance management)

The test suite includes 80+ tests covering unit testing, integration testing, and shell script validation.

## Test Structure

### Core Framework

- **`test_framework.sh`** - Lightweight testing framework with assertions and utilities
- **`run_all_tests.sh`** - Main test runner for all plugins and test types
- **`run_shellcheck.sh`** - ShellCheck validation runner for code quality

### GCP Plugin Tests

- **`test_gcommands_unit.sh`** - Unit tests for utility functions (getdate, genv, parameter validation)
- **`test_gcommands_integration.sh`** - Integration tests for command logic and patterns
- **`run_tests.sh`** - Individual test runner for gcommands plugin

### AWS Plugin Tests

- **`test_awscommands_unit.sh`** - Unit tests for utility functions
- **`test_awscommands_integration.sh`** - Integration tests for command patterns
- **`run_awscommands_tests.sh`** - Individual test runner for awscommands plugin

## Running Tests

### Run All Tests (Recommended)

```bash
# Run complete test suite for both plugins
./tests/run_all_tests.sh
```

### Run Tests by Plugin

```bash
# Test only GCP plugin
./tests/run_all_tests.sh gcommands

# Test only AWS plugin
./tests/run_all_tests.sh awscommands
```

### Run Tests by Type

```bash
# Run only unit tests for all plugins
./tests/run_all_tests.sh all unit

# Run only integration tests for all plugins
./tests/run_all_tests.sh all integration

# Run unit tests for specific plugin
./tests/run_all_tests.sh gcommands unit
./tests/run_all_tests.sh awscommands unit
```

### Individual Test Runners

```bash
# Run GCP plugin tests directly
./tests/run_tests.sh
./tests/run_tests.sh unit
./tests/run_tests.sh integration

# Run AWS plugin tests directly
./tests/run_awscommands_tests.sh
./tests/run_awscommands_tests.sh unit
./tests/run_awscommands_tests.sh integration

# Run shell validation
./tests/run_shellcheck.sh
./tests/run_shellcheck.sh --details
```

## Test Coverage

### Unit Tests

#### Common Utilities (Both Plugins)

- **Date handling**: Cross-platform date calculation (macOS/Linux)
- **Environment variables**: User and prefix configuration handling
- **Parameter validation**: Command argument validation and error handling
- **OS type detection**: OSTYPE-based branching for platform compatibility

#### GCP Plugin Specific

- **Configuration display**: `genv` function behavior and gcloud context
- **Instance naming**: `GUSER` and `GPREFIX` usage patterns
- **Label generation**: Cloud-custodian compliant label formatting

#### AWS Plugin Specific

- **Profile display**: AWS profile and region detection
- **Tag generation**: Cloud-custodian compliant tag formatting
- **Username detection**: Multiple SSH username handling

### Integration Tests

#### Function Availability

- **Core functions**: Verifies all main functions are loaded and accessible
- **Command construction**: Tests parameter handling and validation logic
- **Error messaging**: Validates usage messages and help text

#### Resource Management Patterns

- **Instance operations**: Create, start, stop, delete command patterns
- **Storage operations**: Disk/volume creation and attachment patterns
- **Network operations**: SSH access and port forwarding patterns
- **Tagging/Labeling**: Cloud-custodian compliance validation

#### Cross-Platform Compatibility

- **Darwin/Linux**: Date command handling differences
- **Environment variables**: Fallback behavior and error handling
- **Path resolution**: CLI tool availability checking

## Test Framework Features

### Core Functionality

- **Colorized output**: Green/red indicators for success/failure with clear visual feedback
- **Comprehensive assertions**: `assert_equals`, `assert_contains`, `assert_exit_code`, `assert_not_empty`, etc.
- **Mock command system**: Isolates tests from external dependencies (no real cloud CLI calls)
- **Temporary file management**: Automatic cleanup of test artifacts
- **Detailed reporting**: Test statistics, failure details, and summary reporting

### Advanced Features

- **Test isolation**: Each test runs in a clean environment
- **Error capture**: Detailed error messages and stack traces for failures
- **Performance tracking**: Basic timing information for test execution
- **CI/CD compatibility**: Proper exit codes and machine-readable output
- **Debugging support**: Verbose mode for troubleshooting test issues

## Prerequisites

- **Shell**: Bash or Zsh shell environment
- **System utilities**: Standard Unix tools (date, awk, grep, sed)
- **No cloud CLI required**: Tests use comprehensive mocking to avoid external dependencies
- **Permissions**: Read access to plugin files and write access for temporary test files

## Environment Variables

### Mock Test Environment

Tests automatically set up mock environment variables:

```bash
# GCP plugin testing
GUSER="testuser"
GPREFIX="testprefix"

# AWS plugin testing  
AWSUSER="testuser"
AWSPREFIX="testprefix"

# Platform detection
OSTYPE="linux-gnu"  # or "darwin" for macOS testing
```

### Test Configuration

- Tests run in isolated environments to prevent interference
- Mock functions replace actual cloud CLI calls
- Temporary files are created in secure locations with automatic cleanup

## Exit Codes

- **0**: All tests passed successfully
- **1**: One or more tests failed
- **2**: Test framework error or setup failure
- **3**: Missing dependencies or configuration issues

## Adding New Tests

### For Utility Functions

1. **Unit tests**: Add to appropriate `test_*_unit.sh` file
2. **Test naming**: Use descriptive names like `test_getdate_returns_future_date()`
3. **Assertions**: Use framework functions (`assert_equals`, `assert_contains`, etc.)
4. **Cleanup**: Ensure tests clean up any temporary resources

### For Command Integration

1. **Integration tests**: Add to appropriate `test_*_integration.sh` file
2. **Mock dependencies**: Use mock functions instead of real CLI calls
3. **Parameter testing**: Test both valid and invalid parameter combinations
4. **Error handling**: Verify proper error messages and exit codes

### Development Workflow

```bash
# 1. Write failing test first (TDD approach)
./tests/run_all_tests.sh gcommands unit

# 2. Implement functionality
vim replicated-gcommands.plugin.zsh

# 3. Verify test passes
./tests/run_all_tests.sh gcommands unit

# 4. Run full test suite to check for regressions
./tests/run_all_tests.sh

# 5. Validate shell script quality
./tests/run_shellcheck.sh
```

### Test Function Template

```bash
test_new_function_behavior() {
    # Arrange
    local expected="expected_value"
    local input="test_input"
    
    # Act
    local result=$(new_function "$input")
    
    # Assert
    assert_equals "$expected" "$result" "Function should return expected value"
}
```

## Troubleshooting

### Common Issues

- **Permission errors**: Ensure execute permissions on test scripts (`chmod +x tests/*.sh`)
- **Path issues**: Run tests from repository root directory
- **Mock failures**: Check that mock functions are properly defined in test files
- **Platform differences**: Use `OSTYPE` variable for platform-specific logic

### Debugging Tests

```bash
# Enable verbose output
DEBUG=1 ./tests/run_all_tests.sh

# Run specific failing test
./tests/test_gcommands_unit.sh test_specific_function

# Check shell script syntax
./tests/run_shellcheck.sh --details
```