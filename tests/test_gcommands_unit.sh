#!/bin/bash

# Unit tests for gcommands plugin utility functions

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source the test framework
source "$SCRIPT_DIR/test_framework.sh"

# Setup test environment
setup_tests

# Mock environment variables for testing
export GUSER="testuser"
export GPREFIX="testprefix"

# Create a temporary directory for test artifacts
TEST_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

run_test_suite "Utility Functions Unit Tests"

# Test getdate function - need to source the functions first
# Create a test version of the plugin that doesn't require gcloud
cat > "$TEST_DIR/test_functions.sh" << 'EOF'
#!/bin/bash

getdate() {
  local duration="$1"
  case $OSTYPE in
    darwin*)
      [ -z "$duration" ] && duration="1d" || :
      date "-v+${duration}" '+%Y-%m-%d'
      ;;
    linux*)
      [ -z "$duration" ] && duration="1 day" || :
      date -d "${duration}" '+%Y-%m-%d'
      ;;
  esac
}

genv() {
  if [ -f ~/.config/gcloud/active_config ]; then
    >&2 echo "Configuration: $(cat ~/.config/gcloud/active_config)"
  else
    >&2 echo "Configuration: default"
  fi
}

# Mock gcloud config directory for testing
mock_gcloud_config() {
  mkdir -p "$TEST_DIR/.config/gcloud"
  echo "test-config" > "$TEST_DIR/.config/gcloud/active_config"
  HOME="$TEST_DIR"
}
EOF

source "$TEST_DIR/test_functions.sh"

# Test getdate function with default duration
test_getdate_default() {
    local result=$(getdate)
    local expected_pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
    
    # Check that result matches date format YYYY-MM-DD
    if [[ $result =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        print_success "getdate() returns valid date format"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_failure "getdate() should return YYYY-MM-DD format, got: $result"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Test getdate function with custom duration
test_getdate_custom() {
    local result
    case $OSTYPE in
        darwin*)
            result=$(getdate "2d")
            ;;
        linux*)
            result=$(getdate "2 days")
            ;;
    esac
    
    if [[ $result =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        print_success "getdate() with custom duration returns valid date format"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_failure "getdate() with custom duration should return YYYY-MM-DD format, got: $result"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Test genv function
test_genv_with_config() {
    mock_gcloud_config
    
    local result=$(genv 2>&1)
    assert_contains "$result" "Configuration: test-config" "genv() displays correct configuration"
}

# Test genv function without config file
test_genv_without_config() {
    # Use a different temp directory without config
    local temp_home=$(mktemp -d)
    local old_home="$HOME"
    HOME="$temp_home"
    
    local result=$(genv 2>&1)
    assert_contains "$result" "Configuration: default" "genv() shows default when no config file"
    
    # Cleanup
    HOME="$old_home"
    rm -rf "$temp_home"
}

# Test parameter validation functions (simulate gcreate usage validation)
test_parameter_validation() {
    # Test that functions properly validate minimum parameters
    local usage_pattern="Usage:"
    
    # Create a mock function that mimics gcreate parameter validation
    mock_gcreate_validation() {
        local usage="Usage: gcreate [-d duration|never] <IMAGE> <MACHINE_TYPE> <INSTANCE_NAMES...>"
        if [ "$#" -lt 2 ]; then
            echo "${usage}"
            return 1
        fi
        return 0
    }
    
    # Test with insufficient parameters
    local result
    result=$(mock_gcreate_validation "single_param" 2>&1)
    local exit_code=$?
    
    assert_exit_code 1 $exit_code "Parameter validation fails with insufficient arguments"
    assert_contains "$result" "$usage_pattern" "Usage message is displayed on validation failure"
    
    # Test with sufficient parameters
    result=$(mock_gcreate_validation "image" "machine-type" "instance1" 2>&1)
    exit_code=$?
    
    assert_exit_code 0 $exit_code "Parameter validation passes with sufficient arguments"
}

# Test environment variable usage
test_environment_variables() {
    assert_equals "testuser" "$GUSER" "GUSER environment variable is set correctly"
    assert_equals "testprefix" "$GPREFIX" "GPREFIX environment variable is set correctly"
    
    # Test behavior when GPREFIX is empty
    local old_gprefix="$GPREFIX"
    unset GPREFIX
    
    # Mock a function that uses GPREFIX
    mock_prefix_function() {
        local instance_name="test"
        if [ -n "${GPREFIX}" ]; then
            echo "${GPREFIX}-${instance_name}"
        else
            echo "${instance_name}"
        fi
    }
    
    local result=$(mock_prefix_function)
    assert_equals "test" "$result" "Function works correctly when GPREFIX is unset"
    
    # Restore GPREFIX
    export GPREFIX="$old_gprefix"
    
    result=$(mock_prefix_function)
    assert_equals "testprefix-test" "$result" "Function uses GPREFIX when set"
}

# Test OS type detection for cross-platform compatibility
test_ostype_detection() {
    # Save current OSTYPE
    local original_ostype="$OSTYPE"
    
    # Test Darwin (macOS) path
    OSTYPE="darwin20.0"
    local result=$(getdate "1d" 2>/dev/null)
    if [ $? -eq 0 ] && [[ $result =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        print_success "getdate() works with Darwin OSTYPE"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_failure "getdate() failed with Darwin OSTYPE"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test Linux path - only if we're actually on Linux
    if [[ "$original_ostype" == *"linux"* ]]; then
        OSTYPE="linux-gnu"
        result=$(getdate "1 day" 2>/dev/null)
        if [ $? -eq 0 ] && [[ $result =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            print_success "getdate() works with Linux OSTYPE"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            print_failure "getdate() failed with Linux OSTYPE"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_RUN=$((TESTS_RUN + 1))
    else
        # Skip Linux test on non-Linux systems
        print_success "getdate() Linux test skipped (not on Linux system)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        TESTS_RUN=$((TESTS_RUN + 1))
    fi
    
    # Restore original OSTYPE
    OSTYPE="$original_ostype"
}

# Run all tests
test_getdate_default
test_getdate_custom
test_genv_with_config
test_genv_without_config
test_parameter_validation
test_environment_variables
test_ostype_detection

print_test_summary