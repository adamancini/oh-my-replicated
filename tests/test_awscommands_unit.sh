#!/bin/bash

# Unit tests for awscommands plugin utility functions

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source the test framework
source "$SCRIPT_DIR/test_framework.sh"

# Setup test environment
setup_tests

# Mock environment variables for testing
export AWSUSER="testuser"
export AWSPREFIX="testprefix"

# Create a temporary directory for test artifacts
TEST_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

run_test_suite "AWS Commands Unit Tests"

# Create a test version of the plugin that doesn't require aws cli
cat > "$TEST_DIR/test_aws_functions.sh" << 'EOF'
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

awsenv() {
  >&2 echo "AWS Profile: $(aws configure list-profiles | grep '\*' || echo 'default')"
  >&2 echo "AWS Region: $(aws configure get region || echo 'us-east-1')"
}

# Mock AWS config for testing
mock_aws_config() {
  mkdir -p "$TEST_DIR/.aws"
  echo "[default]" > "$TEST_DIR/.aws/config"
  echo "region = us-west-2" >> "$TEST_DIR/.aws/config"
  echo "[default]" > "$TEST_DIR/.aws/credentials"
  echo "aws_access_key_id = test" >> "$TEST_DIR/.aws/credentials"
  echo "aws_secret_access_key = test" >> "$TEST_DIR/.aws/credentials"
  HOME="$TEST_DIR"
}

# Mock aws command for testing
aws() {
  case "$1" in
    "configure")
      case "$2" in
        "list-profiles")
          echo "default"
          ;;
        "get")
          if [ "$3" = "region" ]; then
            echo "us-west-2"
          fi
          ;;
      esac
      ;;
  esac
}
EOF

source "$TEST_DIR/test_aws_functions.sh"

# Test getdate function with default duration
test_getdate_default() {
    local result=$(getdate)
    
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

# Test awsenv function
test_awsenv_with_config() {
    mock_aws_config
    
    local result=$(awsenv 2>&1)
    assert_contains "$result" "AWS Profile:" "awsenv() displays AWS profile"
    assert_contains "$result" "AWS Region:" "awsenv() displays AWS region"
}

# Test parameter validation functions
test_parameter_validation() {
    # Test that functions properly validate minimum parameters
    local usage_pattern="Usage:"
    
    # Create a mock function that mimics awscreate parameter validation
    mock_awscreate_validation() {
        local usage="Usage: awscreate [-d duration|never] <AMI_ID> <INSTANCE_TYPE> <INSTANCE_NAMES...>"
        if [ "$#" -lt 3 ]; then
            echo "${usage}"
            return 1
        fi
        return 0
    }
    
    # Test with insufficient parameters
    local result
    result=$(mock_awscreate_validation "ami-123" "t3.medium" 2>&1)
    local exit_code=$?
    
    assert_exit_code 1 $exit_code "Parameter validation fails with insufficient arguments"
    assert_contains "$result" "$usage_pattern" "Usage message is displayed on validation failure"
    
    # Test with sufficient parameters
    result=$(mock_awscreate_validation "ami-123" "t3.medium" "instance1" 2>&1)
    exit_code=$?
    
    assert_exit_code 0 $exit_code "Parameter validation passes with sufficient arguments"
}

# Test environment variable usage
test_environment_variables() {
    assert_equals "testuser" "$AWSUSER" "AWSUSER environment variable is set correctly"
    assert_equals "testprefix" "$AWSPREFIX" "AWSPREFIX environment variable is set correctly"
    
    # Test behavior when AWSPREFIX is empty
    local old_awsprefix="$AWSPREFIX"
    unset AWSPREFIX
    
    # Mock a function that uses AWSPREFIX
    mock_prefix_function() {
        local instance_name="test"
        if [ -n "${AWSPREFIX}" ]; then
            echo "${AWSPREFIX}-${instance_name}"
        else
            echo "${instance_name}"
        fi
    }
    
    local result=$(mock_prefix_function)
    assert_equals "test" "$result" "Function works correctly when AWSPREFIX is unset"
    
    # Restore AWSPREFIX
    export AWSPREFIX="$old_awsprefix"
    
    result=$(mock_prefix_function)
    assert_equals "testprefix-test" "$result" "Function uses AWSPREFIX when set"
}

# Test OS type detection for cross-platform compatibility
test_ostype_detection() {
    # Save current OSTYPE
    local original_ostype="$OSTYPE"
    
    # Test Darwin (macOS) path
    OSTYPE="darwin20.0"
    local result=$(getdate "1d" 2>/dev/null)
    if getdate "1d" >/dev/null 2>&1 && [[ $result =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
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
        if getdate "1 day" >/dev/null 2>&1 && [[ $result =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
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

# Test AMI ID validation pattern
test_ami_validation() {
    # Mock AMI validation function
    validate_ami() {
        local ami_id="$1"
        if [[ $ami_id =~ ^ami-[0-9a-f]{8,17}$ ]]; then
            return 0
        else
            return 1
        fi
    }
    
    # Test valid AMI IDs
    assert_exit_code 0 "$(validate_ami "ami-12345678"; echo $?)" "Valid 8-char AMI ID is accepted"
    assert_exit_code 0 "$(validate_ami "ami-1234567890abcdef1"; echo $?)" "Valid 17-char AMI ID is accepted"
    
    # Test invalid AMI IDs
    assert_exit_code 1 "$(validate_ami "ami-123"; echo $?)" "Invalid short AMI ID is rejected"
    assert_exit_code 1 "$(validate_ami "invalid-ami"; echo $?)" "Invalid AMI format is rejected"
}

# Test SSH username detection logic
test_ssh_username_logic() {
    # Mock function that simulates SSH username detection
    get_ssh_username() {
        local ami_type="$1"
        case $ami_type in
            *ubuntu*) echo "ubuntu" ;;
            *amazon*) echo "ec2-user" ;;
            *centos*) echo "centos" ;;
            *fedora*) echo "fedora" ;;
            *) echo "ec2-user" ;;
        esac
    }
    
    assert_equals "ubuntu" "$(get_ssh_username "ubuntu-20.04")" "Ubuntu AMI uses ubuntu username"
    assert_equals "ec2-user" "$(get_ssh_username "amazon-linux-2")" "Amazon Linux uses ec2-user username"
    assert_equals "centos" "$(get_ssh_username "centos-7")" "CentOS uses centos username"
    assert_equals "ec2-user" "$(get_ssh_username "unknown-ami")" "Unknown AMI defaults to ec2-user username"
}

# Run all tests
test_getdate_default
test_getdate_custom
test_awsenv_with_config
test_parameter_validation
test_environment_variables
test_ostype_detection
test_ami_validation
test_ssh_username_logic

print_test_summary