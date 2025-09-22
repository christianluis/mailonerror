#!/bin/bash

# test_config.sh - Test configuration parsing and validation for mailonerror

set -euo pipefail

# Test directory and script paths
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(dirname "$TEST_DIR")"
LIB_DIR="$SCRIPT_DIR/lib"

# Source the config library
source "$LIB_DIR/config.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
declare -a FAILED_TESTS=()

# Logging functions for tests
test_log() {
    echo "[TEST] $*"
}

test_error() {
    echo "[TEST ERROR] $*" >&2
}

# Mock logging functions (required by config.sh)
log_verbose() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo "[VERBOSE] $*" >&2
    fi
}

log_error() {
    echo "[ERROR] $*" >&2
}

# Test framework functions
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    test_log "Running test: $test_name"
    
    # Reset global variables before each test
    reset_config_variables
    
    if "$test_function"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        test_log "✓ PASSED: $test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$test_name")
        test_log "✗ FAILED: $test_name"
    fi
    echo
}

# Reset configuration variables to defaults
reset_config_variables() {
    MOE_sendgrid_api_key=""
    MOE_from_name=""
    MOE_from=""
    MOE_to=""
    MOE_subject=""
    MOE_html_body_file=""
    MOE_retry_interval_seconds=10
    MOE_max_retry_seconds=300
    MOE_slack_webhook_url=""
    MOE_slack_message_file=""
    
    # Reset override variables
    MOE_OVERRIDE_FROM=""
    MOE_OVERRIDE_TO=""
    MOE_OVERRIDE_SUBJECT=""
    MOE_OVERRIDE_HTML_BODY_FILE=""
    MOE_OVERRIDE_SENDGRID_KEY=""
    MOE_OVERRIDE_SLACK_WEBHOOK=""
    MOE_OVERRIDE_SLACK_MESSAGE_FILE=""
    
    # Reset other variables
    MOE_CONFIG_FILE=""
    MOE_DEFAULT_CONFIG_FILE="$HOME/.mailonerror/config"
    MOE_DRY_RUN="false"
    MOE_SELF_TEST="false"
}

# Test: Basic configuration loading from file
test_basic_config_loading() {
    local temp_config
    temp_config=$(mktemp)
    
    cat > "$temp_config" << 'EOF'
sendgrid_api_key="SG.test123"
from="test@example.com"
to="admin@example.com"
subject="Test subject"
retry_interval_seconds=5
max_retry_seconds=60
EOF
    
    CONFIG_FILE="$temp_config"
    
    # Mock validation to avoid errors during testing
    validate_config() { return 0; }
    apply_overrides() { return 0; }
    
    load_config
    
    rm -f "$temp_config"
    
    [[ "$sendgrid_api_key" == "SG.test123" ]] && \
    [[ "$from" == "test@example.com" ]] && \
    [[ "$to" == "admin@example.com" ]] && \
    [[ "$subject" == "Test subject" ]] && \
    [[ "$retry_interval_seconds" == "5" ]] && \
    [[ "$max_retry_seconds" == "60" ]]
}

# Test: Configuration with quotes
test_config_with_quotes() {
    local temp_config
    temp_config=$(mktemp)
    
    cat > "$temp_config" << 'EOF'
sendgrid_api_key="SG.quoted_key"
from='single@example.com'
from_name="Alert System"
subject="Command '${COMMAND}' failed"
EOF
    
    CONFIG_FILE="$temp_config"
    
    validate_config() { return 0; }
    apply_overrides() { return 0; }
    
    load_config
    
    rm -f "$temp_config"
    
    [[ "$sendgrid_api_key" == "SG.quoted_key" ]] && \
    [[ "$from" == "single@example.com" ]] && \
    [[ "$from_name" == "Alert System" ]] && \
    [[ "$subject" == "Command '\${COMMAND}' failed" ]]
}

# Test: Configuration with comments and empty lines
test_config_with_comments() {
    local temp_config
    temp_config=$(mktemp)
    
    cat > "$temp_config" << 'EOF'
# This is a comment
sendgrid_api_key="SG.test456"

# Another comment
from="test2@example.com"

to="admin2@example.com"
EOF
    
    CONFIG_FILE="$temp_config"
    
    validate_config() { return 0; }
    apply_overrides() { return 0; }
    
    load_config
    
    rm -f "$temp_config"
    
    [[ "$sendgrid_api_key" == "SG.test456" ]] && \
    [[ "$from" == "test2@example.com" ]] && \
    [[ "$to" == "admin2@example.com" ]]
}

# Test: Tilde expansion in file paths
test_tilde_expansion() {
    local temp_config
    temp_config=$(mktemp)
    
    cat > "$temp_config" << 'EOF'
html_body_file="~/templates/custom.html"
slack_message_file="~/templates/slack.txt"
EOF
    
    CONFIG_FILE="$temp_config"
    
    validate_config() { return 0; }
    apply_overrides() { return 0; }
    
    load_config
    
    rm -f "$temp_config"
    
    [[ "$html_body_file" == "$HOME/templates/custom.html" ]] && \
    [[ "$slack_message_file" == "$HOME/templates/slack.txt" ]]
}

# Test: Command line overrides
test_command_line_overrides() {
    validate_config() { return 0; }
    
    # Set some base configuration
    sendgrid_api_key="SG.original"
    from="original@example.com"
    to="original-to@example.com"
    
    # Set overrides
    OVERRIDE_FROM="override@example.com"
    OVERRIDE_TO="override-to@example.com"
    OVERRIDE_SENDGRID_KEY="SG.override"
    
    apply_overrides
    
    [[ "$from" == "override@example.com" ]] && \
    [[ "$to" == "override-to@example.com" ]] && \
    [[ "$sendgrid_api_key" == "SG.override" ]]
}

# Test: Email validation
test_email_validation() {
    # Set required fields
    sendgrid_api_key="SG.test789"
    from="valid@example.com"
    to="valid-to@example.com"
    retry_interval_seconds=10
    max_retry_seconds=300
    
    # Test valid emails
    if validate_config 2>/dev/null; then
        # Test invalid from email
        from="invalid-email"
        if validate_config 2>/dev/null; then
            return 1  # Should have failed
        fi
        
        # Reset and test invalid to email
        from="valid@example.com"
        to="invalid-email"
        if validate_config 2>/dev/null; then
            return 1  # Should have failed
        fi
        
        return 0  # All validations worked as expected
    else
        return 1  # Valid config should have passed
    fi
}

# Test: Numeric validation
test_numeric_validation() {
    sendgrid_api_key="SG.test"
    from="test@example.com"
    to="test@example.com"
    
    # Test valid numbers
    retry_interval_seconds=10
    max_retry_seconds=300
    if ! validate_config 2>/dev/null; then
        return 1
    fi
    
    # Test invalid retry_interval_seconds
    retry_interval_seconds="not_a_number"
    max_retry_seconds=300
    if validate_config 2>/dev/null; then
        return 1  # Should have failed
    fi
    
    # Test invalid max_retry_seconds
    retry_interval_seconds=10
    max_retry_seconds="not_a_number"
    if validate_config 2>/dev/null; then
        return 1  # Should have failed
    fi
    
    return 0
}

# Test: Missing required fields
test_missing_required_fields() {
    # Test missing API key
    sendgrid_api_key=""
    from="test@example.com"
    to="test@example.com"
    retry_interval_seconds=10
    max_retry_seconds=300
    
    if validate_config 2>/dev/null; then
        return 1  # Should have failed
    fi
    
    # Test missing from email
    sendgrid_api_key="SG.test"
    from=""
    to="test@example.com"
    
    if validate_config 2>/dev/null; then
        return 1  # Should have failed
    fi
    
    # Test missing to email
    sendgrid_api_key="SG.test"
    from="test@example.com"
    to=""
    
    if validate_config 2>/dev/null; then
        return 1  # Should have failed
    fi
    
    return 0
}

# Test: Default template setting
test_default_templates() {
    SCRIPT_DIR="/fake/script/dir"  # Set fake script dir for testing
    
    set_default_templates
    
    [[ "$subject" == "Command '\${COMMAND}' failed on \${HOSTNAME}" ]] && \
    [[ "$html_body_file" == "/fake/script/dir/templates/default.html" ]]
}

# Test: Non-existent config file
test_nonexistent_config_file() {
    CONFIG_FILE="/nonexistent/config/file"
    
    validate_config() { return 0; }
    apply_overrides() { return 0; }
    
    # Should not fail even if config file doesn't exist
    load_config
    
    # Should use default values
    [[ "$retry_interval_seconds" == "10" ]] && \
    [[ "$max_retry_seconds" == "300" ]]
}

# Main test runner
main() {
    echo "===================="
    echo "mailonerror Config Tests"
    echo "===================="
    echo
    
    # Run all tests
    run_test "Basic configuration loading" test_basic_config_loading
    run_test "Configuration with quotes" test_config_with_quotes
    run_test "Configuration with comments" test_config_with_comments
    run_test "Tilde expansion" test_tilde_expansion
    run_test "Command line overrides" test_command_line_overrides
    run_test "Email validation" test_email_validation
    run_test "Numeric validation" test_numeric_validation
    run_test "Missing required fields" test_missing_required_fields
    run_test "Default templates" test_default_templates
    run_test "Non-existent config file" test_nonexistent_config_file
    
    # Print summary
    echo "===================="
    echo "Test Summary"
    echo "===================="
    echo "Tests run: $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo
        echo "Failed tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        exit 1
    else
        echo
        echo "All tests passed! ✓"
        exit 0
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi