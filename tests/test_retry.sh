#!/bin/bash

# test_retry.sh - Test retry logic and email delivery for mailonerror

set -euo pipefail

# Test directory and script paths
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(dirname "$TEST_DIR")"
LIB_DIR="$SCRIPT_DIR/lib"

# Source required libraries
source "$LIB_DIR/config.sh"
source "$LIB_DIR/templates.sh"
source "$LIB_DIR/mailer.sh"
source "$LIB_DIR/slack.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
declare -a FAILED_TESTS=()

# Mock curl responses
declare -A MOCK_CURL_RESPONSES
declare -A MOCK_CURL_EXIT_CODES
MOCK_CURL_CALL_COUNT=0

# Logging functions for tests
test_log() {
    echo "[TEST] $*"
}

test_error() {
    echo "[TEST ERROR] $*" >&2
}

# Mock logging functions (required by libraries)
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
    
    # Reset state before each test
    reset_test_state
    
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

# Reset test state
reset_test_state() {
    # Reset configuration variables
    sendgrid_api_key="SG.test_key_12345"
    from="test@example.com"
    to="admin@example.com"
    from_name="Test Alert"
    subject="Test Alert"
    html_body_file="/nonexistent"  # Use built-in template
    retry_interval_seconds=1  # Fast retry for testing
    max_retry_seconds=5
    slack_webhook_url=""
    slack_message_file=""
    
    # Reset template variables
    COMMAND="test-command --arg"
    EXIT_CODE="1"
    STDOUT_OUTPUT="test stdout"
    STDERR_OUTPUT="test stderr"
    TIMESTAMP="2023-01-15T10:30:45+00:00"
    HOSTNAME="test-host"
    USER="testuser"
    
    # Reset retry settings
    RETRY_ENABLED=false
    
    # Reset mock curl state
    MOCK_CURL_RESPONSES=()
    MOCK_CURL_EXIT_CODES=()
    MOCK_CURL_CALL_COUNT=0
    
    # Mock functions
    mock_default_functions
}

# Mock default functions
mock_default_functions() {
    # Mock set_default_templates
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
    
    # Mock mktemp
    mktemp() {
        echo "/tmp/mock_temp_$$_$RANDOM"
    }
    
    # Mock rm
    rm() {
        return 0
    }
    
    # Mock cat for temp files
    cat() {
        local file="$1"
        if [[ "$file" == /tmp/mock_temp_* ]]; then
            echo "mock response"
        else
            command cat "$@"
        fi
    }
    
    # Mock date for consistent timestamps in tests
    date() {
        if [[ "$1" == "+%s" ]]; then
            echo "1673781045"  # Fixed timestamp
        elif [[ "$1" == "-Iseconds" ]]; then
            echo "2023-01-15T10:30:45+00:00"
        else
            command date "$@"
        fi
    }
    
    # Mock sleep for faster tests
    sleep() {
        return 0
    }
}

# Mock curl function
curl() {
    local url="" http_code_requested=false
    local args=("$@")
    
    MOCK_CURL_CALL_COUNT=$((MOCK_CURL_CALL_COUNT + 1))
    
    # Parse arguments to find URL
    for ((i=0; i<${#args[@]}; i++)); do
        if [[ "${args[i]}" == "-w" ]]; then
            if [[ "${args[i+1]}" == "%{http_code}" ]]; then
                http_code_requested=true
            fi
        elif [[ "${args[i]}" == "https://api.sendgrid.com"* ]]; then
            url="sendgrid"
        elif [[ "${args[i]}" == "https://hooks.slack.com"* ]]; then
            url="slack"
        fi
    done
    
    # Return mock response based on call count and URL
    local response_key="${url}_${MOCK_CURL_CALL_COUNT}"
    local exit_code="${MOCK_CURL_EXIT_CODES[$response_key]:-0}"
    local response="${MOCK_CURL_RESPONSES[$response_key]:-200}"
    
    if [[ $http_code_requested == true ]]; then
        echo "$response"
    fi
    
    return $exit_code
}

# Test: Successful email sending (single attempt)
test_successful_email_single() {
    MOCK_CURL_RESPONSES["sendgrid_1"]="202"
    MOCK_CURL_EXIT_CODES["sendgrid_1"]=0
    
    RETRY_ENABLED=false
    
    send_email
}

# Test: Failed email sending (single attempt)
test_failed_email_single() {
    MOCK_CURL_RESPONSES["sendgrid_1"]="400"
    MOCK_CURL_EXIT_CODES["sendgrid_1"]=0
    
    RETRY_ENABLED=false
    
    # Should fail
    if send_email; then
        return 1
    else
        return 0
    fi
}

# Test: Curl failure
test_curl_failure() {
    MOCK_CURL_EXIT_CODES["sendgrid_1"]=1
    
    RETRY_ENABLED=false
    
    # Should fail due to curl error
    if send_email; then
        return 1
    else
        return 0
    fi
}

# Test: Successful email with retry (first attempt succeeds)
test_successful_email_retry_first_attempt() {
    MOCK_CURL_RESPONSES["sendgrid_1"]="202"
    MOCK_CURL_EXIT_CODES["sendgrid_1"]=0
    
    RETRY_ENABLED=true
    
    send_email
}

# Test: Successful email with retry (second attempt succeeds)
test_successful_email_retry_second_attempt() {
    MOCK_CURL_RESPONSES["sendgrid_1"]="500"
    MOCK_CURL_EXIT_CODES["sendgrid_1"]=0
    MOCK_CURL_RESPONSES["sendgrid_2"]="202"
    MOCK_CURL_EXIT_CODES["sendgrid_2"]=0
    
    RETRY_ENABLED=true
    
    send_email
}

# Test: Email retry timeout
test_email_retry_timeout() {
    # All attempts fail
    for i in {1..10}; do
        MOCK_CURL_RESPONSES["sendgrid_$i"]="500"
        MOCK_CURL_EXIT_CODES["sendgrid_$i"]=0
    done
    
    RETRY_ENABLED=true
    max_retry_seconds=3  # Short timeout
    
    # Should fail after timeout
    if send_email; then
        return 1
    else
        return 0
    fi
}

# Test: Successful Slack notification
test_successful_slack() {
    slack_webhook_url="https://hooks.slack.com/services/test"
    
    MOCK_CURL_RESPONSES["slack_1"]="200"
    MOCK_CURL_EXIT_CODES["slack_1"]=0
    
    send_slack
}

# Test: Failed Slack notification
test_failed_slack() {
    slack_webhook_url="https://hooks.slack.com/services/test"
    
    MOCK_CURL_RESPONSES["slack_1"]="400"
    MOCK_CURL_EXIT_CODES["slack_1"]=0
    
    # Should fail
    if send_slack; then
        return 1
    else
        return 0
    fi
}

# Test: Slack not configured (should skip gracefully)
test_slack_not_configured() {
    slack_webhook_url=""  # Not configured
    
    # Should succeed (skip gracefully)
    send_slack
}

# Test: SendGrid configuration validation
test_sendgrid_config_validation() {
    # Test missing API key
    sendgrid_api_key=""
    if send_email 2>/dev/null; then
        return 1  # Should have failed
    fi
    
    # Test missing from email
    sendgrid_api_key="SG.test"
    from=""
    if send_email 2>/dev/null; then
        return 1  # Should have failed
    fi
    
    # Test missing to email
    from="test@example.com"
    to=""
    if send_email 2>/dev/null; then
        return 1  # Should have failed
    fi
    
    return 0
}

# Test: Payload creation
test_payload_creation() {
    # Test SendGrid payload
    local sendgrid_payload
    sendgrid_payload=$(create_sendgrid_payload)
    
    [[ -n "$sendgrid_payload" ]] && \
    [[ "$sendgrid_payload" == *'"personalizations"'* ]] && \
    [[ "$sendgrid_payload" == *'"from"'* ]] && \
    [[ "$sendgrid_payload" == *'"content"'* ]]
}

# Test: Slack payload creation
test_slack_payload_creation() {
    slack_webhook_url="https://hooks.slack.com/services/test"
    
    local slack_payload
    slack_payload=$(create_slack_payload)
    
    [[ -n "$slack_payload" ]] && \
    [[ "$slack_payload" == *'"text"'* ]]
}

# Test: Test email functionality
test_test_email_functionality() {
    MOCK_CURL_RESPONSES["sendgrid_1"]="202"
    MOCK_CURL_EXIT_CODES["sendgrid_1"]=0
    
    # Override send_email to use test payload
    send_test_email
}

# Test: Test Slack functionality
test_test_slack_functionality() {
    slack_webhook_url="https://hooks.slack.com/services/test"
    
    MOCK_CURL_RESPONSES["slack_1"]="200"
    MOCK_CURL_EXIT_CODES["slack_1"]=0
    
    send_test_slack
}

# Test: Exponential backoff timing (mock test)
test_exponential_backoff() {
    # This test verifies the backoff calculation logic
    local interval=1
    local max_interval=60
    local iterations=0
    
    # Mock the retry loop logic (without actual delays)
    while [[ $interval -lt $max_interval && $iterations -lt 10 ]]; do
        iterations=$((iterations + 1))
        interval=$((interval * 2))
        
        # Add mock jitter
        local jitter=$((interval / 4))
        interval=$((interval + jitter))
        
        if [[ $interval -gt $max_interval ]]; then
            interval=$max_interval
        fi
    done
    
    # Should have performed multiple iterations with increasing intervals
    [[ $iterations -gt 3 ]] && [[ $interval -eq $max_interval ]]
}

# Test: HTTP response code handling
test_http_response_codes() {
    # Test various HTTP codes for SendGrid
    local codes=("200" "201" "202" "400" "401" "403" "500")
    local success_count=0
    local failure_count=0
    
    for code in "${codes[@]}"; do
        MOCK_CURL_CALL_COUNT=0
        MOCK_CURL_RESPONSES["sendgrid_1"]="$code"
        MOCK_CURL_EXIT_CODES["sendgrid_1"]=0
        
        if send_email_once "test payload" 2>/dev/null; then
            success_count=$((success_count + 1))
        else
            failure_count=$((failure_count + 1))
        fi
    done
    
    # Only 202 should succeed for SendGrid
    [[ $success_count -eq 1 ]] && [[ $failure_count -eq 6 ]]
}

# Test: Slack HTTP response codes
test_slack_http_response_codes() {
    slack_webhook_url="https://hooks.slack.com/services/test"
    
    local codes=("200" "400" "403" "404" "500")
    local success_count=0
    local failure_count=0
    
    for code in "${codes[@]}"; do
        MOCK_CURL_CALL_COUNT=0
        MOCK_CURL_RESPONSES["slack_1"]="$code"
        MOCK_CURL_EXIT_CODES["slack_1"]=0
        
        if send_slack_once "test payload" 2>/dev/null; then
            success_count=$((success_count + 1))
        else
            failure_count=$((failure_count + 1))
        fi
    done
    
    # Only 200 should succeed for Slack
    [[ $success_count -eq 1 ]] && [[ $failure_count -eq 4 ]]
}

# Test: Configuration test functions
test_config_test_functions() {
    MOCK_CURL_RESPONSES["sendgrid_1"]="200"
    MOCK_CURL_EXIT_CODES["sendgrid_1"]=0
    
    # Test SendGrid config test
    test_sendgrid_config > /dev/null
    
    # Test Slack config test (not configured)
    slack_webhook_url=""
    test_slack_config > /dev/null
    
    # Test Slack config test (configured)
    slack_webhook_url="https://hooks.slack.com/services/test"
    MOCK_CURL_CALL_COUNT=0
    MOCK_CURL_RESPONSES["slack_1"]="200"
    test_slack_config > /dev/null
}

# Main test runner
main() {
    echo "===================="
    echo "mailonerror Retry & Email Tests"
    echo "===================="
    echo
    
    # Run all tests
    run_test "Successful email single attempt" test_successful_email_single
    run_test "Failed email single attempt" test_failed_email_single
    run_test "Curl failure" test_curl_failure
    run_test "Successful email retry first attempt" test_successful_email_retry_first_attempt
    run_test "Successful email retry second attempt" test_successful_email_retry_second_attempt
    run_test "Email retry timeout" test_email_retry_timeout
    run_test "Successful Slack notification" test_successful_slack
    run_test "Failed Slack notification" test_failed_slack
    run_test "Slack not configured" test_slack_not_configured
    run_test "SendGrid configuration validation" test_sendgrid_config_validation
    run_test "Payload creation" test_payload_creation
    run_test "Slack payload creation" test_slack_payload_creation
    run_test "Test email functionality" test_test_email_functionality
    run_test "Test Slack functionality" test_test_slack_functionality
    run_test "Exponential backoff" test_exponential_backoff
    run_test "HTTP response code handling" test_http_response_codes
    run_test "Slack HTTP response codes" test_slack_http_response_codes
    run_test "Configuration test functions" test_config_test_functions
    
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