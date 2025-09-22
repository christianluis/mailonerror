#!/bin/bash

# test_templates.sh - Test template rendering and variable substitution for mailonerror

set -euo pipefail

# Test directory and script paths
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(dirname "$TEST_DIR")"
LIB_DIR="$SCRIPT_DIR/lib"

# Source the templates library
source "$LIB_DIR/templates.sh"

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

# Mock logging functions (required by templates.sh)
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
    reset_template_variables
    
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

# Reset template variables to test values
reset_template_variables() {
    COMMAND="test-command --arg value"
    EXIT_CODE="1"
    STDOUT_OUTPUT="This is stdout output"
    STDERR_OUTPUT="This is stderr output"
    TIMESTAMP="2023-01-15T10:30:45+00:00"
    HOSTNAME="test-host"
    USER="testuser"
    
    # Reset configuration variables
    subject=""
    html_body_file=""
    slack_webhook_url=""
    slack_message_file=""
    
    # Mock set_default_templates function
    set_default_templates() {
        if [[ -z "$subject" ]]; then
            subject="Command '\${COMMAND}' failed on \${HOSTNAME}"
        fi
        if [[ -z "$html_body_file" ]]; then
            html_body_file="$SCRIPT_DIR/templates/default.html"
        fi
        if [[ -z "$slack_message_file" && -n "$slack_webhook_url" ]]; then
            slack_message_file="$SCRIPT_DIR/templates/slack.txt"
        fi
    }
}

# Test: Basic variable substitution
test_basic_variable_substitution() {
    local input="Command: \${COMMAND}, Exit: \${EXIT_CODE}, Host: \${HOSTNAME}"
    local expected="Command: test-command --arg value, Exit: 1, Host: test-host"
    local result
    
    result=$(substitute_variables "$input")
    
    [[ "$result" == "$expected" ]]
}

# Test: All template variables
test_all_template_variables() {
    local input="\${COMMAND}|\${EXIT_CODE}|\${STDOUT}|\${STDERR}|\${TIMESTAMP}|\${HOSTNAME}|\${USER}"
    local expected="test-command --arg value|1|This is stdout output|This is stderr output|2023-01-15T10:30:45+00:00|test-host|testuser"
    local result
    
    result=$(substitute_variables "$input")
    
    [[ "$result" == "$expected" ]]
}

# Test: HTML escaping
test_html_escaping() {
    COMMAND="echo '<script>alert(\"test\")</script>'"
    STDOUT_OUTPUT="Output with <tags> & \"quotes\""
    
    local input="Command: \${COMMAND}, Output: \${STDOUT}"
    local result
    
    result=$(substitute_variables "$input" "html")
    
    # Check that HTML characters are escaped
    [[ "$result" == *"&lt;script&gt;"* ]] && \
    [[ "$result" == *"&amp;"* ]] && \
    [[ "$result" == *"&quot;"* ]]
}

# Test: JSON escaping
test_json_escaping() {
    COMMAND=$'echo "Hello\nWorld"'
    STDOUT_OUTPUT=$'Line 1\nLine 2\tTabbed'
    
    local input="Command: \${COMMAND}, Output: \${STDOUT}"
    local result

    result=$(substitute_variables "$input" "json")

    [[ "$result" == *"\\\"Hello\\nWorld\\\""* ]] && \
    [[ "$result" == *"\\n"* ]] && \
    [[ "$result" == *"\\t"* ]]
}

# Test: Subject rendering
test_subject_rendering() {
    subject="Alert: \${COMMAND} failed with code \${EXIT_CODE} on \${HOSTNAME}"
    
    local result expected
    expected="Alert: test-command --arg value failed with code 1 on test-host"
    result=$(render_subject)
    
    [[ "$result" == "$expected" ]]
}

# Test: Default subject rendering
test_default_subject_rendering() {
    subject=""  # Empty subject should use default
    
    local result expected
    expected="Command 'test-command --arg value' failed on test-host"
    result=$(render_subject)
    
    [[ "$result" == "$expected" ]]
}

# Test: HTML body rendering with built-in template
test_html_body_builtin_template() {
    html_body_file="/nonexistent/file"  # Force use of built-in template
    
    local result
    result=$(render_html_body)
    
    # Check that result contains expected elements
    [[ "$result" == *"<!DOCTYPE html>"* ]] && \
    [[ "$result" == *"test-command --arg value"* ]] && \
    [[ "$result" == *"This is stdout output"* ]] && \
    [[ "$result" == *"This is stderr output"* ]] && \
    [[ "$result" == *"test-host"* ]] && \
    [[ "$result" == *"testuser"* ]]
}

# Test: HTML body rendering with file template
test_html_body_file_template() {
    local temp_template
    temp_template=$(mktemp)
    
    cat > "$temp_template" << 'EOF'
<html>
<body>
<h1>Failed Command: ${COMMAND}</h1>
<p>Exit Code: ${EXIT_CODE}</p>
<pre>${STDOUT}</pre>
<pre>${STDERR}</pre>
</body>
</html>
EOF
    
    html_body_file="$temp_template"
    
    local result
    result=$(render_html_body)
    
    rm -f "$temp_template"
    
    # Check that template was processed correctly
    [[ "$result" == *"Failed Command: test-command --arg value"* ]] && \
    [[ "$result" == *"Exit Code: 1"* ]] && \
    [[ "$result" == *"This is stdout output"* ]] && \
    [[ "$result" == *"This is stderr output"* ]]
}

# Test: Slack message rendering with built-in template
test_slack_message_builtin() {
    slack_webhook_url="https://hooks.slack.com/services/test"
    slack_message_file="/nonexistent/file"  # Force use of built-in template
    
    local result
    result=$(render_slack_message)
    
    # Check that result contains expected elements
    [[ "$result" == *"Command Failed on test-host"* ]] && \
    [[ "$result" == *"test-command --arg value"* ]] && \
    [[ "$result" == *"Exit Code"* ]] && \
    [[ "$result" == *"This is stdout output"* ]] && \
    [[ "$result" == *"This is stderr output"* ]]
}

# Test: Slack message rendering with file template
test_slack_message_file() {
    local temp_template
    temp_template=$(mktemp)
    
    cat > "$temp_template" << 'EOF'
ALERT: Command ${COMMAND} failed!
Exit code: ${EXIT_CODE}
Host: ${HOSTNAME}
User: ${USER}
Time: ${TIMESTAMP}
EOF
    
    slack_webhook_url="https://hooks.slack.com/services/test"
    slack_message_file="$temp_template"
    
    local result
    result=$(render_slack_message)
    
    rm -f "$temp_template"
    
    # Check that template was processed correctly
    [[ "$result" == *"ALERT: Command test-command --arg value failed!"* ]] && \
    [[ "$result" == *"Exit code: 1"* ]] && \
    [[ "$result" == *"Host: test-host"* ]] && \
    [[ "$result" == *"User: testuser"* ]] && \
    [[ "$result" == *"Time: 2023-01-15T10:30:45+00:00"* ]]
}

# Test: Slack message skipped when not configured
test_slack_message_not_configured() {
    slack_webhook_url=""  # Not configured
    
    local result
    result=$(render_slack_message)
    
    # Should return empty/success when not configured
    [[ $? -eq 0 ]]
}

# Test: SendGrid JSON payload creation
test_sendgrid_json_payload() {
    subject="Test Subject: \${COMMAND}"
    html_body_file="/nonexistent"  # Use built-in template
    
    # Mock config variables
    from="test@example.com"
    to="admin@example.com"
    from_name="Test Alert"
    
    local result
    result=$(create_sendgrid_payload)
    
    # Check that JSON is valid and contains expected fields
    [[ "$result" == *'"personalizations"'* ]] && \
    [[ "$result" == *'"from"'* ]] && \
    [[ "$result" == *'"content"'* ]] && \
    [[ "$result" == *'"test@example.com"'* ]] && \
    [[ "$result" == *'"admin@example.com"'* ]] && \
    [[ "$result" == *'"Test Alert"'* ]] && \
    [[ "$result" == *'"Test Subject: test-command --arg value"'* ]]
}

# Test: SendGrid JSON payload without from_name
test_sendgrid_json_payload_no_name() {
    subject="Test Subject"
    html_body_file="/nonexistent"
    
    from="test@example.com"
    to="admin@example.com"
    from_name=""  # No from name
    
    local result
    result=$(create_sendgrid_payload)
    
    # Check that JSON doesn't include name field
    [[ "$result" == *'"email":"test@example.com"'* ]] && \
    [[ "$result" != *'"name"'* ]]
}

# Test: Slack JSON payload creation
test_slack_json_payload() {
    slack_webhook_url="https://hooks.slack.com/services/test"
    slack_message_file="/nonexistent"  # Use built-in template
    
    local result
    result=$(create_slack_payload)
    
    # Check that JSON is valid and contains expected fields
    [[ "$result" == *'"text"'* ]] && \
    [[ "$result" == *"Command Failed on test-host"* ]] && \
    [[ "$result" == *"test-command --arg value"* ]]
}

# Test: Special characters in variables
test_special_characters() {
    COMMAND="echo 'Special chars: $@#%^&*()'"
    STDOUT_OUTPUT="Output with newlines\nand tabs\tand quotes\"'"
    
    local result
    result=$(substitute_variables "Command: \${COMMAND}\nOutput: \${STDOUT}" "json")
    
    # Should handle special characters without breaking
    [[ "$result" == *"Special chars"* ]] && \
    [[ "$result" == *"\\n"* ]] && \
    [[ "$result" == *"\\t"* ]]
}

# Test: Empty variables
test_empty_variables() {
    COMMAND=""
    STDOUT_OUTPUT=""
    STDERR_OUTPUT=""
    
    local result
    result=$(substitute_variables "Cmd:\${COMMAND}, Out:\${STDOUT}, Err:\${STDERR}")
    
    [[ "$result" == "Cmd:, Out:, Err:" ]]
}

# Test: Template rendering test function
test_template_rendering_function() {
    slack_webhook_url="https://hooks.slack.com/services/test"
    
    # This should not fail and should produce output
    test_template_rendering > /dev/null
    
    [[ $? -eq 0 ]]
}

# Main test runner
main() {
    echo "===================="
    echo "mailonerror Template Tests"
    echo "===================="
    echo
    
    # Run all tests
    run_test "Basic variable substitution" test_basic_variable_substitution
    run_test "All template variables" test_all_template_variables
    run_test "HTML escaping" test_html_escaping
    run_test "JSON escaping" test_json_escaping
    run_test "Subject rendering" test_subject_rendering
    run_test "Default subject rendering" test_default_subject_rendering
    run_test "HTML body built-in template" test_html_body_builtin_template
    run_test "HTML body file template" test_html_body_file_template
    run_test "Slack message built-in template" test_slack_message_builtin
    run_test "Slack message file template" test_slack_message_file
    run_test "Slack message not configured" test_slack_message_not_configured
    run_test "SendGrid JSON payload" test_sendgrid_json_payload
    run_test "SendGrid JSON payload without name" test_sendgrid_json_payload_no_name
    run_test "Slack JSON payload" test_slack_json_payload
    run_test "Special characters" test_special_characters
    run_test "Empty variables" test_empty_variables
    run_test "Template rendering function" test_template_rendering_function
    
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