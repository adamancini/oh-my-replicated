#!/bin/bash

# Script to run shellcheck validation on all shell scripts in the repository

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  ShellCheck Validation Report${NC}"
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

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Check if shellcheck is available
check_shellcheck() {
    if ! command -v shellcheck >/dev/null 2>&1; then
        print_error "shellcheck is not installed"
        echo "To install shellcheck:"
        echo "  macOS: brew install shellcheck"
        echo "  Ubuntu: sudo apt install shellcheck"
        echo "  CentOS: sudo yum install shellcheck"
        exit 1
    fi
    
    local version=$(shellcheck --version | grep version: | awk '{print $2}')
    print_success "shellcheck version $version found"
    echo
}

# Find all shell scripts
find_shell_scripts() {
    cd "$PROJECT_DIR" || exit 1
    find . -type f \( -name "*.sh" -o -name "*.zsh" \) | grep -v ".git" | grep -v ".specstory" | sort
}

# Run shellcheck on a single file
check_file() {
    local file="$1"
    local relative_path="${file#$PROJECT_DIR/}"
    
    echo "Checking: $relative_path"
    
    # Run shellcheck and capture output
    local output
    local exit_code=0
    
    if output=$(shellcheck "$file" 2>&1); then
        print_success "  No issues found"
        return 0
    else
        exit_code=$?
        
        # Count different severity levels
        local errors=$(echo "$output" | grep -c "SC.*error" || echo "0")
        local warnings=$(echo "$output" | grep -c "SC.*warning" || echo "0")
        local info=$(echo "$output" | grep -c "SC.*info" || echo "0")
        local style=$(echo "$output" | grep -c "SC.*style" || echo "0")
        
        local total=$((errors + warnings + info + style))
        
        if [ "$errors" -gt 0 ]; then
            print_error "  $errors error(s), $warnings warning(s), $info info, $style style issues"
        elif [ "$warnings" -gt 0 ]; then
            print_warning "  $warnings warning(s), $info info, $style style issues"
        else
            echo -e "  ${BLUE}$info info, $style style issues${NC}"
        fi
        
        # Show details if requested
        if [ "$SHOW_DETAILS" = "true" ]; then
            echo "$output" | sed 's/^/    /'
            echo
        fi
        
        return $exit_code
    fi
}

# Summary counters
total_files=0
clean_files=0
files_with_errors=0
files_with_warnings=0
files_with_minor_issues=0

# Main execution
main() {
    local show_details=false
    local exit_on_error=false
    
    # Parse command line options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--details)
                show_details=true
                export SHOW_DETAILS=true
                shift
                ;;
            -e|--exit-on-error)
                exit_on_error=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -d, --details      Show detailed shellcheck output"
                echo "  -e, --exit-on-error Exit on first error"
                echo "  -h, --help         Show this help message"
                echo ""
                echo "Exit codes:"
                echo "  0  All files passed or only minor issues"
                echo "  1  Files with errors found"
                echo "  2  Files with warnings found (no errors)"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use -h for help"
                exit 1
                ;;
        esac
    done
    
    print_header
    check_shellcheck
    
    print_section "Scanning Shell Scripts"
    
    local files=()
    while IFS= read -r file; do
        files+=("$file")
    done < <(find_shell_scripts)
    
    if [ ${#files[@]} -eq 0 ]; then
        print_warning "No shell scripts found"
        exit 0
    fi
    
    echo "Found ${#files[@]} shell script(s)"
    echo
    
    print_section "ShellCheck Results"
    
    for file in "${files[@]}"; do
        ((total_files++))
        
        if check_file "$file"; then
            ((clean_files++))
        else
            local exit_code=$?
            if [ $exit_code -eq 1 ]; then
                # shellcheck returned 1 (issues found)
                local output
                output=$(shellcheck "$file" 2>&1)
                
                if echo "$output" | grep -q "SC.*error"; then
                    ((files_with_errors++))
                    if [ "$exit_on_error" = "true" ]; then
                        echo
                        print_error "Exiting on first error (--exit-on-error specified)"
                        exit 1
                    fi
                elif echo "$output" | grep -q "SC.*warning"; then
                    ((files_with_warnings++))
                else
                    ((files_with_minor_issues++))
                fi
            fi
        fi
        
        echo
    done
    
    print_section "Summary"
    
    echo "Total files checked: $total_files"
    print_success "Clean files: $clean_files"
    
    if [ $files_with_errors -gt 0 ]; then
        print_error "Files with errors: $files_with_errors"
    fi
    
    if [ $files_with_warnings -gt 0 ]; then
        print_warning "Files with warnings: $files_with_warnings"
    fi
    
    if [ $files_with_minor_issues -gt 0 ]; then
        echo -e "${BLUE}Files with minor issues: $files_with_minor_issues${NC}"
    fi
    
    echo
    
    # Determine exit code
    if [ $files_with_errors -gt 0 ]; then
        print_error "ShellCheck found errors in $files_with_errors file(s)"
        echo "Run with --details to see full output"
        exit 1
    elif [ $files_with_warnings -gt 0 ]; then
        print_warning "ShellCheck found warnings in $files_with_warnings file(s)"
        echo "Run with --details to see full output"
        exit 2
    else
        print_success "All files passed ShellCheck validation!"
        if [ $files_with_minor_issues -gt 0 ]; then
            echo "Some files have minor style/info issues that don't affect functionality"
        fi
        exit 0
    fi
}

# Run main function with all arguments
main "$@"