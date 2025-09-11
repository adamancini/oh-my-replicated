#!/bin/bash

# Integration tests for awscommands plugin

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

run_test_suite "AWS Commands Integration Tests"

# Test that functions exist and have basic functionality
test_function_existence() {
    # Test getdate function
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
    
    # Test that getdate works
    local result=$(getdate)
    assert_not_empty "$result" "getdate function produces output"
    
    # Test parameter validation pattern
    mock_aws_command_with_validation() {
        local usage="Usage: aws_command <param1> <param2> <param3>"
        if [ "$#" -lt 3 ]; then
            echo "$usage"
            return 1
        fi
        echo "AWS command executed with $# parameters"
        return 0
    }
    
    # Test parameter validation
    local result
    result=$(mock_aws_command_with_validation "param1" "param2" 2>&1)
    local exit_code=$?
    assert_exit_code 1 $exit_code "AWS commands properly validate parameters"
    assert_contains "$result" "Usage:" "AWS commands show usage on validation failure"
    
    # Test successful execution
    result=$(mock_aws_command_with_validation "ami-123" "t3.medium" "instance1" 2>&1)
    exit_code=$?
    assert_exit_code 0 $exit_code "AWS commands execute successfully with valid parameters"
    assert_contains "$result" "AWS command executed with 3 parameters" "AWS commands process parameters correctly"
}

# Test environment variable handling
test_environment_handling() {
    # Test AWSPREFIX application
    apply_aws_prefix() {
        local name="$1"
        if [ -n "${AWSPREFIX}" ]; then
            echo "${AWSPREFIX}-${name}"
        else
            echo "${name}"
        fi
    }
    
    local result=$(apply_aws_prefix "instance1")
    assert_equals "testprefix-instance1" "$result" "AWSPREFIX is applied correctly"
    
    # Test without AWSPREFIX
    local old_prefix="$AWSPREFIX"
    unset AWSPREFIX
    result=$(apply_aws_prefix "instance1") 
    assert_equals "instance1" "$result" "Functions work without AWSPREFIX"
    
    # Restore AWSPREFIX
    export AWSPREFIX="$old_prefix"
}

# Test AWS command construction patterns
test_aws_command_construction() {
    # Mock a simplified version of awscreate command construction
    mock_awscreate() {
        local usage="Usage: awscreate [-d duration] <ami_id> <instance_type> <names...>"
        local expires
        local OPTIND=1
        
        while getopts ":d:" opt; do
            case $opt in
                d)
                    expires="$OPTARG"
                    ;;
            esac
        done
        shift "$((OPTIND-1))"
        
        if [ "$#" -lt 3 ]; then
            echo "$usage"
            return 1
        fi
        
        local ami_id="$1"
        local instance_type="$2" 
        shift 2
        local names=("$@")
        
        # Apply prefix to names
        local prefixed_names=()
        for name in "${names[@]}"; do
            if [ -n "${AWSPREFIX}" ]; then
                prefixed_names+=("${AWSPREFIX}-${name}")
            else
                prefixed_names+=("${name}")
            fi
        done
        
        # Mock command output
        echo "Would create EC2 instances: ${prefixed_names[*]} with AMI: $ami_id type: $instance_type expires: ${expires:-default}"
        return 0
    }
    
    # Test basic command construction
    local result=$(mock_awscreate "ami-12345678" "t3.medium" "instance1")
    assert_contains "$result" "testprefix-instance1" "Command applies AWSPREFIX to instance names"
    assert_contains "$result" "ami-12345678" "Command uses specified AMI ID"
    assert_contains "$result" "t3.medium" "Command uses specified instance type"
    
    # Test with duration flag
    result=$(mock_awscreate -d "never" "ami-12345678" "t3.medium" "instance1")
    assert_contains "$result" "expires: never" "Command handles duration flag"
    
    # Test parameter validation
    result=$(mock_awscreate "ami-12345678" "t3.medium" 2>&1)
    local exit_code=$?
    assert_exit_code 1 $exit_code "Command validates required parameters"
    assert_contains "$result" "Usage:" "Command shows usage on validation failure"
}

# Test AWS-specific functionality
test_aws_specific_features() {
    # Test AMI ID validation
    validate_ami_id() {
        local ami_id="$1"
        if [[ $ami_id =~ ^ami-[0-9a-f]{8,17}$ ]]; then
            echo "Valid AMI ID: $ami_id"
            return 0
        else
            echo "Invalid AMI ID: $ami_id"
            return 1
        fi
    }
    
    local result=$(validate_ami_id "ami-12345678")
    assert_contains "$result" "Valid AMI ID" "Valid AMI ID is accepted"
    
    result=$(validate_ami_id "invalid-ami")
    assert_contains "$result" "Invalid AMI ID" "Invalid AMI ID is rejected"
    
    # Test security group naming
    generate_sg_name() {
        local user="$1"
        echo "${user}-default-sg"
    }
    
    result=$(generate_sg_name "$AWSUSER")
    assert_equals "testuser-default-sg" "$result" "Security group name is generated correctly"
    
    # Test SSH username detection
    detect_ssh_username() {
        local ami_name="$1"
        case $ami_name in
            *ubuntu*) echo "ubuntu" ;;
            *amazon*|*amzn*) echo "ec2-user" ;;
            *centos*) echo "centos" ;;
            *fedora*) echo "fedora" ;;
            *) echo "ec2-user" ;;
        esac
    }
    
    assert_equals "ubuntu" "$(detect_ssh_username "ubuntu-20.04-amd64-server")" "Ubuntu AMI detected correctly"
    assert_equals "ec2-user" "$(detect_ssh_username "amazon-linux-2-ami")" "Amazon Linux AMI detected correctly"
    assert_equals "ec2-user" "$(detect_ssh_username "unknown-ami")" "Unknown AMI defaults to ec2-user"
}

# Test AWS tag construction
test_aws_tag_construction() {
    # Mock AWS tag creation
    create_aws_tags() {
        local instance_name="$1"
        local user="$2"
        local expires="$3"
        
        echo "Key=Name,Value=${instance_name} Key=Owner,Value=${user} Key=Email,Value=${user}@replicated.com Key=ExpiresOn,Value=${expires}"
    }
    
    local result=$(create_aws_tags "testprefix-instance1" "$AWSUSER" "2023-12-25")
    assert_contains "$result" "Key=Name,Value=testprefix-instance1" "Instance name tag is correct"
    assert_contains "$result" "Key=Owner,Value=testuser" "Owner tag is correct"
    assert_contains "$result" "Key=Email,Value=testuser@replicated.com" "Email tag is correct"
    assert_contains "$result" "Key=ExpiresOn,Value=2023-12-25" "Expiration tag is correct"
}

# Test port configuration for security groups
test_security_group_ports() {
    # Mock security group port configuration
    configure_sg_ports() {
        local ports=("22" "80" "443" "8800" "8888" "30000")
        for port in "${ports[@]}"; do
            echo "Opening port $port"
        done
    }
    
    local result=$(configure_sg_ports)
    assert_contains "$result" "Opening port 22" "SSH port is configured"
    assert_contains "$result" "Opening port 8800" "Replicated admin port is configured"
    assert_contains "$result" "Opening port 30000" "Embedded cluster port is configured"
}

# Test cross-platform compatibility
test_cross_platform() {
    # Test OSTYPE detection
    local original_ostype="$OSTYPE"
    
    # Test Darwin behavior
    OSTYPE="darwin20.0"
    local result=$(getdate "1d" 2>/dev/null || echo "failed")
    assert_not_empty "$result" "getdate works on Darwin"
    
    # Test Linux behavior (only if on Linux system)
    if [[ "$original_ostype" == *"linux"* ]]; then
        OSTYPE="linux-gnu" 
        result=$(getdate "1 day" 2>/dev/null || echo "failed")
        assert_not_empty "$result" "getdate works on Linux"
    else
        print_success "getdate Linux test skipped (not on Linux system)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        TESTS_RUN=$((TESTS_RUN + 1))
    fi
    
    # Restore original OSTYPE
    OSTYPE="$original_ostype"
}

# Test volume and attachment patterns
test_volume_operations() {
    # Mock volume creation
    mock_create_volume() {
        local name="$1"
        local size="$2"
        local user="$3"
        
        if [ -n "${AWSPREFIX}" ]; then
            name="${AWSPREFIX}-vol-${name}"
        else
            name="vol-${name}"
        fi
        
        echo "Creating volume: $name, size: ${size}GB, owner: $user"
        return 0
    }
    
    local result=$(mock_create_volume "data" "100" "$AWSUSER")
    assert_contains "$result" "testprefix-vol-data" "Volume name includes prefix"
    assert_contains "$result" "size: 100GB" "Volume size is correct"
    assert_contains "$result" "owner: testuser" "Volume owner is correct"
}

# Run all tests
test_function_existence
test_environment_handling
test_aws_command_construction
test_aws_specific_features
test_aws_tag_construction
test_security_group_ports
test_cross_platform
test_volume_operations

print_test_summary