#!/bin/bash

# Comprehensive test runner for all oh-my-replicated plugins
# Usage: ./run_all_tests.sh [gcommands|awscommands|all] [unit|integration|all]

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  Oh My Replicated - All Plugin Tests${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo
}

print_section() {
    echo -e "${YELLOW}--- $1 ---${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"
    
    # Check if we're in the right directory
    if [ ! -f "$SCRIPT_DIR/../replicated-gcommands.plugin.zsh" ] || [ ! -f "$SCRIPT_DIR/../replicated-awscommands.plugin.zsh" ]; then
        print_error "Plugin files not found. Are you in the right directory?"
        exit 1
    fi
    
    # Check for required commands
    if ! command -v bash >/dev/null 2>&1; then
        print_error "bash is required but not installed"
        exit 1
    fi
    
    if ! command -v date >/dev/null 2>&1; then
        print_error "date command is required but not found"
        exit 1
    fi
    
    print_success "All prerequisites met"
    echo
}

# Run gcommands tests
run_gcommands_tests() {
    local test_type="${1:-all}"
    print_section "Running GCommands Tests ($test_type)"
    
    local unit_result=0
    local integration_result=0
    
    case "$test_type" in
        unit|all)
            if [ -f "$SCRIPT_DIR/test_gcommands_unit.sh" ]; then
                echo "Running gcommands unit tests..."
                if "$SCRIPT_DIR/test_gcommands_unit.sh"; then
                    print_success "GCommands unit tests passed"
                else
                    print_error "GCommands unit tests failed"
                    unit_result=1
                fi
            else
                print_error "GCommands unit test file not found"
                unit_result=1
            fi
            
            [ "$test_type" = "unit" ] && return $unit_result
            echo
            ;;
    esac
    
    case "$test_type" in
        integration|all)
            if [ -f "$SCRIPT_DIR/test_gcommands_simplified.sh" ]; then
                echo "Running gcommands integration tests..."
                if "$SCRIPT_DIR/test_gcommands_simplified.sh"; then
                    print_success "GCommands integration tests passed"
                else
                    print_error "GCommands integration tests failed"
                    integration_result=1
                fi
            else
                print_error "GCommands integration test file not found"
                integration_result=1
            fi
            ;;
    esac
    
    return $((unit_result + integration_result))
}

# Run awscommands tests
run_awscommands_tests() {
    local test_type="${1:-all}"
    print_section "Running AWSCommands Tests ($test_type)"
    
    local unit_result=0
    local integration_result=0
    
    case "$test_type" in
        unit|all)
            if [ -f "$SCRIPT_DIR/test_awscommands_unit.sh" ]; then
                echo "Running awscommands unit tests..."
                if "$SCRIPT_DIR/test_awscommands_unit.sh"; then
                    print_success "AWSCommands unit tests passed"
                else
                    print_error "AWSCommands unit tests failed"
                    unit_result=1
                fi
            else
                print_error "AWSCommands unit test file not found"
                unit_result=1
            fi
            
            [ "$test_type" = "unit" ] && return $unit_result
            echo
            ;;
    esac
    
    case "$test_type" in
        integration|all)
            if [ -f "$SCRIPT_DIR/test_awscommands_integration.sh" ]; then
                echo "Running awscommands integration tests..."
                if "$SCRIPT_DIR/test_awscommands_integration.sh"; then
                    print_success "AWSCommands integration tests passed"
                else
                    print_error "AWSCommands integration tests failed"
                    integration_result=1
                fi
            else
                print_error "AWSCommands integration test file not found"
                integration_result=1
            fi
            ;;
    esac
    
    return $((unit_result + integration_result))
}

# Show usage
show_usage() {
    echo "Usage: $0 [PLUGIN] [TEST_TYPE]"
    echo ""
    echo "PLUGIN options:"
    echo "  gcommands    Run only gcommands plugin tests"
    echo "  awscommands  Run only awscommands plugin tests"  
    echo "  all          Run tests for all plugins (default)"
    echo ""
    echo "TEST_TYPE options:"
    echo "  unit         Run only unit tests"
    echo "  integration  Run only integration tests"
    echo "  all          Run all test types (default)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Run all tests for all plugins"
    echo "  $0 gcommands                 # Run all gcommands tests"
    echo "  $0 awscommands unit          # Run only awscommands unit tests"
    echo "  $0 all integration           # Run integration tests for all plugins"
    echo ""
    echo "Options:"
    echo "  -h, --help   Show this help message"
}

# Main execution
main() {
    local plugin="${1:-all}"
    local test_type="${2:-all}"
    
    # Handle help option
    if [ "$plugin" = "-h" ] || [ "$plugin" = "--help" ]; then
        show_usage
        exit 0
    fi
    
    # Validate plugin option
    case "$plugin" in
        gcommands|awscommands|all)
            ;;
        *)
            echo "Error: Unknown plugin '$plugin'"
            echo
            show_usage
            exit 1
            ;;
    esac
    
    # Validate test_type option
    case "$test_type" in
        unit|integration|all)
            ;;
        *)
            echo "Error: Unknown test type '$test_type'"
            echo
            show_usage
            exit 1
            ;;
    esac
    
    print_header
    check_prerequisites
    
    local gcommands_result=0
    local awscommands_result=0
    
    # Run requested tests
    case "$plugin" in
        gcommands)
            run_gcommands_tests "$test_type"
            exit $?
            ;;
        awscommands)
            run_awscommands_tests "$test_type"
            exit $?
            ;;
        all)
            run_gcommands_tests "$test_type"
            gcommands_result=$?
            
            echo
            
            run_awscommands_tests "$test_type"
            awscommands_result=$?
            
            echo
            print_section "Overall Test Summary"
            
            if [ $gcommands_result -eq 0 ]; then
                print_success "GCommands tests: PASSED"
            else
                print_error "GCommands tests: FAILED"
            fi
            
            if [ $awscommands_result -eq 0 ]; then
                print_success "AWSCommands tests: PASSED"
            else
                print_error "AWSCommands tests: FAILED"
            fi
            
            local overall_result=$((gcommands_result + awscommands_result))
            
            echo
            if [ $overall_result -eq 0 ]; then
                print_success "All plugin tests passed!"
                echo -e "${GREEN}Ready for production! 🚀${NC}"
            else
                print_error "Some plugin tests failed"
                echo -e "${RED}Please fix failing tests before proceeding${NC}"
            fi
            
            exit $overall_result
            ;;
    esac
}

# Run main function with all arguments
main "$@"