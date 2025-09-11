#!/bin/bash

# Test runner for gcommands plugin tests
# Usage: ./run_tests.sh [unit|integration|all]

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
    echo -e "${BLUE}  Oh My Replicated - gcommands Tests${NC}"
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
    if [ ! -f "$SCRIPT_DIR/../replicated-gcommands.plugin.zsh" ]; then
        print_error "gcommands plugin not found. Are you in the right directory?"
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

# Run unit tests
run_unit_tests() {
    print_section "Running Unit Tests"
    
    if [ -f "$SCRIPT_DIR/test_gcommands_unit.sh" ]; then
        chmod +x "$SCRIPT_DIR/test_gcommands_unit.sh"
        if "$SCRIPT_DIR/test_gcommands_unit.sh"; then
            print_success "Unit tests passed"
            return 0
        else
            print_error "Unit tests failed"
            return 1
        fi
    else
        print_error "Unit test file not found"
        return 1
    fi
}

# Run integration tests
run_integration_tests() {
    print_section "Running Integration Tests"
    
    if [ -f "$SCRIPT_DIR/test_gcommands_simplified.sh" ]; then
        chmod +x "$SCRIPT_DIR/test_gcommands_simplified.sh"
        if "$SCRIPT_DIR/test_gcommands_simplified.sh"; then
            print_success "Integration tests passed"
            return 0
        else
            print_error "Integration tests failed"
            return 1
        fi
    else
        print_error "Integration test file not found"
        return 1
    fi
}

# Show usage
show_usage() {
    echo "Usage: $0 [unit|integration|all]"
    echo ""
    echo "Options:"
    echo "  unit         Run only unit tests"
    echo "  integration  Run only integration tests"
    echo "  all          Run all tests (default)"
    echo "  -h, --help   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0           # Run all tests"
    echo "  $0 unit      # Run only unit tests"
    echo "  $0 integration # Run only integration tests"
}

# Main execution
main() {
    local test_type="${1:-all}"
    local unit_result=0
    local integration_result=0
    
    case "$test_type" in
        -h|--help)
            show_usage
            exit 0
            ;;
        unit)
            print_header
            check_prerequisites
            run_unit_tests
            exit $?
            ;;
        integration)
            print_header
            check_prerequisites
            run_integration_tests
            exit $?
            ;;
        all)
            print_header
            check_prerequisites
            
            # Run unit tests
            if ! run_unit_tests; then
                unit_result=1
            fi
            
            echo
            
            # Run integration tests
            if ! run_integration_tests; then
                integration_result=1
            fi
            
            echo
            print_section "Test Summary"
            
            if [ $unit_result -eq 0 ]; then
                print_success "Unit tests: PASSED"
            else
                print_error "Unit tests: FAILED"
            fi
            
            if [ $integration_result -eq 0 ]; then
                print_success "Integration tests: PASSED"
            else
                print_error "Integration tests: FAILED"
            fi
            
            local overall_result=$((unit_result + integration_result))
            
            echo
            if [ $overall_result -eq 0 ]; then
                print_success "All tests passed!"
                echo -e "${GREEN}Ready for production! 🚀${NC}"
            else
                print_error "Some tests failed"
                echo -e "${RED}Please fix failing tests before proceeding${NC}"
            fi
            
            exit $overall_result
            ;;
        *)
            echo "Error: Unknown option '$test_type'"
            echo
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"