#!/bin/bash

# Simple test framework for shell scripts
# Usage: source this file and use assert_equals, assert_contains, etc.

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Print colored output
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_failure() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "$1"
}

# Test assertions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [ "$expected" = "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        print_success "$test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        print_failure "$test_name"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$haystack" == *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        print_success "$test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        print_failure "$test_name"
        echo "  Haystack: '$haystack'"
        echo "  Needle:   '$needle'"
        return 1
    fi
}

assert_exit_code() {
    local expected_code="$1"
    local actual_code="$2"
    local test_name="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [ "$expected_code" = "$actual_code" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        print_success "$test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        print_failure "$test_name"
        echo "  Expected exit code: $expected_code"
        echo "  Actual exit code:   $actual_code"
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local test_name="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [ -n "$value" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        print_success "$test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        print_failure "$test_name"
        echo "  Value was empty"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local test_name="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [ -f "$file" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        print_success "$test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        print_failure "$test_name"
        echo "  File does not exist: $file"
        return 1
    fi
}

# Mock function creator
mock_command() {
    local command_name="$1"
    local mock_output="$2"
    local mock_exit_code="${3:-0}"
    
    eval "$command_name() { echo '$mock_output'; return $mock_exit_code; }"
}

# Test suite runner
run_test_suite() {
    local suite_name="$1"
    echo
    print_info "=== Running $suite_name ==="
    echo
}

# Test summary
print_test_summary() {
    echo
    print_info "=== Test Summary ==="
    echo "Tests run:    $TESTS_RUN"
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        print_success "All tests passed!"
        exit 0
    else
        print_failure "$TESTS_FAILED test(s) failed"
        exit 1
    fi
}

# Setup function - call at start of test file
setup_tests() {
    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
}