# CLAUDE.md

This file provides comprehensive guidance for AI agents working with the Oh My Replicated shell plugin project. This document is optimized for AI-driven development and focuses on effective iteration patterns, test-driven workflows, and shell scripting excellence.

## Project Architecture Overview

### Core Mission

This repository maintains two Oh My Zsh plugins for cloud instance management:

- **`replicated-gcommands.plugin.zsh`** - Google Cloud Platform (GCP) management functions
- **`replicated-awscommands.plugin.zsh`** - Amazon Web Services (AWS) EC2 management functions

Both plugins implement strict cloud-custodian compliance with automated labeling (`owner`, `expires-on`, `managed-by=oh-my-replicated`) and follow consistent architectural patterns for maintainability and reliability.

### Repository Structure

```text
├── replicated-gcommands.plugin.zsh    # GCP plugin (primary implementation)
├── replicated-awscommands.plugin.zsh  # AWS plugin (follows GCP patterns)
├── README.md                          # User documentation
├── tests/                             # Comprehensive test suite (80+ tests)
│   ├── test_framework.sh              # Lightweight testing framework
│   ├── test_*_unit.sh                 # Unit tests for utility functions
│   ├── test_*_integration.sh          # Integration tests for command workflows
│   ├── run_all_tests.sh               # Primary test runner
│   └── run_shellcheck.sh              # Shell script quality validation
├── CLAUDE.md                          # This AI development guide
└── .specstory/                        # AI conversation history preservation
```

## AI Development Workflow

### Test-First Development Approach

**CRITICAL**: This project uses test-driven development. Always follow this sequence:

1. **Establish Baseline**: Run full test suite before any changes

   ```bash
   ./tests/run_all_tests.sh
   ```

2. **Write Failing Tests**: Create tests for new functionality first

   - Unit tests in `test_*_unit.sh` for utility functions
   - Integration tests in `test_*_integration.sh` for command workflows

3. **Implement Incrementally**: Make minimal changes to pass tests

   - Focus on single function at a time
   - Follow established patterns from existing functions

4. **Validate Continuously**: Run targeted tests during development

   ```bash
   ./tests/run_all_tests.sh gcommands unit    # Test specific plugin
   ./tests/run_all_tests.sh all integration   # Test all integration
   ```

5. **Full Validation**: Run complete test suite before finishing

   ```bash
   ./tests/run_all_tests.sh                   # All tests
   ./tests/run_shellcheck.sh                  # Code quality
   ```

### AI Iteration Best Practices

#### Understanding Test Failures

- **Mock Environment**: Tests use comprehensive mocking - no real cloud CLI calls
- **Isolation**: Each test runs in clean environment with mock variables
- **Debugging**: Enable verbose output with `DEBUG=1 ./tests/run_all_tests.sh`
- **Exit Codes**: 0=success, 1=test failures, 2=framework errors, 3=missing dependencies

#### Code Quality Standards

- **ShellCheck Compliance**: All critical issues resolved, warnings are style suggestions
- **Cross-Platform**: Handle macOS (Darwin) and Linux date command differences
- **Error Handling**: Consistent validation with clear usage messages
- **Parameter Validation**: Defensive scripting with availability checks

## Shell Scripting Patterns and Standards

### Function Architecture Templates

#### Standard Function Template

```bash
function_name() {
    local usage="Usage: function_name [-d duration] <REQUIRED> [OPTIONAL...]"
    local param1="" param2=""
    local OPTIND=1
    
    # Validate prerequisites
    validate_required_env || return 1
    show_context  # genv for GCP, awsenv for AWS
    
    # Parse options with proper error handling
    while getopts ":d:h" opt; do
        case $opt in
            d) param1="$OPTARG" ;;
            h) echo "$usage"; return 0 ;;
            \?) echo "Invalid option: -$OPTARG" >&2; echo "$usage" >&2; return 1 ;;
            :) echo "Option -$OPTARG requires an argument" >&2; return 1 ;;
        esac
    done
    shift $((OPTIND-1))
    
    # Validate required parameters
    if [[ $# -lt 1 ]]; then
        echo "Error: Missing required parameter" >&2
        echo "$usage" >&2
        return 1
    fi
    
    # Implementation logic here
    local result
    if ! result=$(command_with_error_handling "$@"); then
        echo "Error: Operation failed" >&2
        return 1
    fi
    
    echo "$result"
}
```

#### Cross-Platform Date Handling

```bash
getdate() {
    local duration="${1:-1d}"
    local result
    
    case "$OSTYPE" in
        darwin*)
            if command -v gdate >/dev/null 2>&1; then
                # Use GNU date if available (homebrew)
                result=$(gdate -d "+${duration/d/ day}" '+%Y-%m-%d' 2>/dev/null)
            else
                # Use BSD date (macOS default)
                result=$(date -j -v "+${duration}" '+%Y-%m-%d' 2>/dev/null)
            fi
            ;;
        linux*|*gnu*)
            result=$(date -d "+${duration/d/ day}" '+%Y-%m-%d' 2>/dev/null)
            ;;
        *)
            printf >&2 'Warning: Unsupported OS type: %s\n' "$OSTYPE"
            result=$(date '+%Y-%m-%d')
            ;;
    esac
    
    if [[ -z "$result" ]]; then
        printf >&2 'Error: Failed to calculate date with duration: %s\n' "$duration"
        return 1
    fi
    
    printf '%s\n' "$result"
}
```

#### Input Validation Patterns

```bash
validate_instance_name() {
    local name="$1"
    
    # Check for valid characters (alphanumeric, hyphens only)
    if [[ ! "$name" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
        printf >&2 'Error: Invalid instance name: %s\n' "$name"
        printf >&2 'Instance names must contain only letters, numbers, and hyphens\n'
        return 1
    fi
    
    # Check length constraints
    if [[ ${#name} -gt 63 ]]; then
        printf >&2 'Error: Instance name too long: %s (max 63 characters)\n' "$name"
        return 1
    fi
    
    return 0
}
```

### Cloud-Custodian Compliance Implementation

#### Required Labels/Tags Pattern

All cloud resources must include these labels:

- `owner=${GUSER}` (GCP) or `Owner=${AWSUSER}` (AWS)
- `expires-on=YYYY-MM-DD` (calculated with `getdate` function)
- `managed-by=oh-my-replicated` (identifies management tool)

#### GCP Label Application

```bash
# Instance creation with labels
gcloud compute instances create "$instance_name" \
    --labels="owner=${GUSER},expires-on=${expires_date},managed-by=oh-my-replicated" \
    --other-parameters...
```

#### AWS Tag Application

```bash
# Instance tagging after creation
aws ec2 create-tags --resources "$instance_id" --tags \
    "Key=Owner,Value=${AWSUSER}" \
    "Key=expires-on,Value=${expires_date}" \
    "Key=managed-by,Value=oh-my-replicated"
```

### Error Handling Best Practices

#### Consistent Error Messages

```bash
# Use stderr for errors, stdout for data
printf >&2 'Error: %s\n' "$error_message"
printf >&2 '%s\n' "$usage_string"
return 1

# For warnings (non-fatal)
printf >&2 'Warning: %s\n' "$warning_message"
```

#### Command Availability Checking

```bash
# Check at plugin load time
if (( ! ${+commands[gcloud]} )); then
    >&2 echo "gcloud not installed, not loading replicated-gcommands plugin"
    return 1
fi

# Check during function execution
if ! command -v aws >/dev/null 2>&1; then
    echo "Error: AWS CLI not found" >&2
    return 1
fi
```

## Test Framework Integration

### Test Function Template

```bash
test_function_name() {
    # Arrange - set up test conditions
    local expected="expected_value"
    local input="test_input"
    
    # Act - execute the function
    local result
    result=$(function_under_test "$input" 2>/dev/null)
    local exit_code=$?
    
    # Assert - verify results
    assert_equals "$expected" "$result" "Function should return expected value"
    assert_equals 0 "$exit_code" "Function should exit successfully"
}
```

### Mock Environment Setup

Tests automatically configure mock environment:

```bash
# Mock environment variables
GUSER="testuser"
GPREFIX="testprefix" 
AWSUSER="testuser"
AWSPREFIX="testprefix"
OSTYPE="linux-gnu"  # or "darwin" for macOS testing

# Mock cloud CLI commands (no real API calls)
gcloud() { echo "mocked gcloud output"; }
aws() { echo "mocked aws output"; }
```

### Assertion Functions Available

- `assert_equals expected actual description`
- `assert_contains haystack needle description`
- `assert_not_empty value description`
- `assert_exit_code expected_code command description`
- `assert_matches pattern string description`

## Cloud Provider Integration Patterns

### GCP Integration Best Practices

- **Configuration Context**: Always show gcloud configuration with `genv`
- **Instance Filtering**: Use `--filter="labels.owner:${GUSER}"` for user scoping
- **Resource Naming**: Combine `${GPREFIX}-${user_provided_name}` when applicable
- **Network Management**: Handle external IP assignment/removal with `gonline`/`gairgap`

### AWS Integration Best Practices

- **Profile Display**: Show active AWS profile and region with `awsenv`
- **Instance Filtering**: Use `--filters "Name=tag:Owner,Values=${AWSUSER}"`
- **SSH Handling**: Try multiple usernames (ubuntu, ec2-user, centos, fedora, admin)
- **Resource Identification**: Use name tags and instance IDs consistently

### Cross-Platform Considerations

- **Date Commands**: Handle BSD date (macOS) vs GNU date (Linux) differences
- **Environment Detection**: Use `$OSTYPE` for platform-specific logic
- **Path Handling**: Use absolute paths and proper quoting
- **Command Substitution**: Prefer `$(command)` over backticks

## Common Development Scenarios

### Adding New Cloud Provider Function

1. **Follow existing patterns** from similar functions in the same plugin
2. **Write unit tests first** for parameter validation and utility logic
3. **Write integration tests** for command construction and workflow
4. **Implement function** following the standard template
5. **Ensure cloud-custodian compliance** with proper labeling
6. **Test cross-platform compatibility** with both Darwin and Linux

### Debugging Test Failures

```bash
# Run specific test with verbose output
DEBUG=1 ./tests/test_gcommands_unit.sh test_specific_function

# Check shell script syntax issues
./tests/run_shellcheck.sh --details

# Run single plugin tests to isolate issues
./tests/run_all_tests.sh gcommands

# Test specific category
./tests/run_all_tests.sh all unit
```

### Handling Platform Differences

```bash
# Detect platform reliably
case "$OSTYPE" in
    darwin*) 
        # macOS-specific logic
        ;;
    linux*|*gnu*) 
        # Linux-specific logic
        ;;
    *)
        # Fallback for unknown platforms
        printf >&2 'Warning: Unsupported OS type: %s\n' "$OSTYPE"
        ;;
esac
```

### Error Recovery Patterns

```bash
# Validate prerequisites early
validate_required_env || return 1

# Check command availability
if ! command -v required_command >/dev/null 2>&1; then
    echo "Error: required_command not found" >&2
    return 1
fi

# Handle cloud CLI errors gracefully
local result
if ! result=$(cloud_command 2>&1); then
    echo "Error: Cloud operation failed: $result" >&2
    return 1
fi
```

## Code Quality Guidelines

### ShellCheck Integration

- **Critical Issues**: Must be resolved (exits with non-zero code)
- **Warnings**: Style suggestions, use discretion for fixes
- **Suppressions**: Use `# shellcheck disable=SCXXXX` sparingly with comments

### Performance Considerations

- **Minimize Cloud API Calls**: Use efficient filtering and batching
- **Cache Environment Variables**: Store frequently used values
- **Optimize Test Execution**: Mock external dependencies completely

### Maintainability Standards

- **Function Length**: Keep functions focused and under 50 lines when possible
- **Naming Conventions**: Use descriptive names with consistent prefixes
- **Documentation**: Include usage strings and parameter descriptions
- **Error Messages**: Provide actionable feedback with clear next steps

## Troubleshooting Guide

### Common Issues and Solutions

#### Test Execution Problems

- **Permission Errors**: Ensure execute permissions (`chmod +x tests/*.sh`)
- **Path Issues**: Always run tests from repository root directory
- **Mock Failures**: Verify mock functions are defined before use

#### Shell Script Issues

- **Quoting Problems**: Use double quotes for variables, single for literals
- **Array Handling**: Be careful with array expansion in different shells
- **Exit Code Handling**: Always check return values of critical operations

#### Cloud Provider Issues

- **Authentication**: Tests don't require real cloud credentials (fully mocked)
- **API Changes**: Update mock responses to match current cloud CLI output
- **Rate Limiting**: Not applicable in test environment due to mocking

### Debug Commands

```bash
# Enable shell tracing for function debugging
set -x; function_name args; set +x

# Show test framework internals
DEBUG=1 ./tests/run_all_tests.sh

# Verify shell script syntax
bash -n plugin_file.zsh

# Check specific ShellCheck rules
shellcheck -e SC2034 plugin_file.zsh
```

This guide provides the essential knowledge for AI agents to effectively develop and maintain the Oh My Replicated shell plugins. Follow the test-driven workflow, maintain cloud-custodian compliance, and leverage the comprehensive test suite to ensure reliable, cross-platform functionality.
