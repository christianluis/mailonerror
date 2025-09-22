#!/bin/bash

# slack.sh - Slack webhook functions for mailonerror

# Send Slack notification
send_slack() {
    # Only proceed if Slack webhook is configured
    if [[ -z "$MOE_slack_webhook_url" ]]; then
        log_verbose "Slack webhook URL not configured, skipping notification"
        return 0
    fi
    
    log_verbose "Preparing to send Slack notification"
    
    # Create Slack payload
    local payload
    payload=$(create_slack_payload)
    
    if [[ -z "$payload" ]]; then
        log_error "Failed to create Slack payload"
        return 1
    fi
    
    log_verbose "Slack payload created successfully"
    
    # Send the notification
    send_slack_once "$payload"
}

# Send Slack notification once (no retry as per requirements)
send_slack_once() {
    local payload="$1"
    local temp_response temp_headers
    temp_response=$(mktemp)
    temp_headers=$(mktemp)
    
    log_verbose "Sending Slack notification via webhook"
    
    # Make the webhook request
    local http_code
    http_code=$(curl -w "%{http_code}" -s \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        -D "$temp_headers" \
        -o "$temp_response" \
        "$MOE_slack_webhook_url")
    
    local curl_exit_code=$?
    
    # Read response and headers
    local response_body response_headers
    response_body=$(cat "$temp_response" 2>/dev/null || echo "")
    response_headers=$(cat "$temp_headers" 2>/dev/null || echo "")
    
    # Cleanup temp files
    rm -f "$temp_response" "$temp_headers"
    
    # Check curl success
    if [[ $curl_exit_code -ne 0 ]]; then
        log_error "Curl failed for Slack webhook with exit code $curl_exit_code"
        return 1
    fi
    
    # Log response details
    log_verbose "Slack webhook HTTP response code: $http_code"
    if [[ "$MOE_VERBOSE" == "true" && -n "$response_body" ]]; then
        log_verbose "Slack response body: $response_body"
    fi
    
    # Check for success (Slack webhooks typically return 200)
    if [[ "$http_code" == "200" ]]; then
        log_verbose "Slack notification sent successfully"
        return 0
    else
        log_error "Slack webhook returned HTTP $http_code"
        if [[ -n "$response_body" ]]; then
            log_error "Slack response: $response_body"
        fi
        return 1
    fi
}

# Test Slack webhook configuration and connectivity
test_slack_config() {
    echo "=== Slack Configuration Test ==="
    
    # Check if Slack is configured
    if [[ -z "$MOE_slack_webhook_url" ]]; then
        echo "- Slack webhook not configured"
        return 0
    fi
    
    # Check configuration
    echo "Configuration:"
    echo "  Webhook URL: ${MOE_slack_webhook_url:0:50}..." # Show only first 50 chars for security
    echo "  Message File: ${MOE_slack_message_file:-<using built-in template>}"
    echo
    
    # Validate webhook URL format
    if [[ "$MOE_slack_webhook_url" =~ ^https://hooks\.slack\.com/services/ ]]; then
        echo "✓ Webhook URL format looks correct"
    else
        echo "⚠ Webhook URL format may be incorrect (should start with https://hooks.slack.com/services/)"
    fi
    
    # Test basic connectivity to Slack webhook (with a minimal test payload)
    echo
    echo "Testing connectivity to Slack webhook..."
    
    local test_payload test_code
    test_payload='{"text": "mailonerror connectivity test"}'
    
    test_code=$(curl -w "%{http_code}" -s -o /dev/null \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$test_payload" \
        "$MOE_slack_webhook_url")
    
    local curl_exit=$?
    
    if [[ $curl_exit -eq 0 ]]; then
        case "$test_code" in
            200)
                echo "✓ Slack webhook connectivity successful"
                ;;
            400)
                echo "✗ Slack webhook returned 400 (bad request - check webhook URL)"
                return 1
                ;;
            403)
                echo "✗ Slack webhook returned 403 (forbidden - check webhook permissions)"
                return 1
                ;;
            404)
                echo "✗ Slack webhook returned 404 (not found - check webhook URL)"
                return 1
                ;;
            *)
                echo "⚠ Slack webhook returned HTTP $test_code"
                ;;
        esac
    else
        echo "✗ Failed to connect to Slack webhook (curl exit code: $curl_exit)"
        return 1
    fi
    
    echo
    echo "Slack configuration test completed."
    return 0
}

# Create a simple test payload for testing
create_test_slack_payload() {
    local test_message
    test_message="🧪 mailonerror test notification

This is a test message sent by mailonerror at $(date -Iseconds).

If you receive this, the Slack webhook configuration is working correctly."
    
    # Escape for JSON
    test_message=$(json_escape "$test_message")
    
    # Create the JSON payload
    cat << EOF
{
    "text": "$test_message"
}
EOF
}

# Send a test Slack message
send_test_slack() {
    if [[ -z "$MOE_slack_webhook_url" ]]; then
        log_verbose "Slack webhook not configured, skipping test"
        return 0
    fi
    
    log_verbose "Sending test Slack message"
    
    # Create and send test payload
    local test_payload
    test_payload=$(create_test_slack_payload)
    
    send_slack_once "$test_payload"
}

# Validate Slack webhook URL format
validate_slack_webhook() {
    local webhook_url="$1"
    
    if [[ -z "$webhook_url" ]]; then
        return 0  # Empty URL is valid (Slack is optional)
    fi
    
    # Check basic URL format
    if [[ ! "$webhook_url" =~ ^https:// ]]; then
        echo "Slack webhook URL must use HTTPS"
        return 1
    fi
    
    # Check if it looks like a Slack webhook URL
    if [[ ! "$webhook_url" =~ ^https://hooks\.slack\.com/ ]]; then
        echo "Slack webhook URL should start with https://hooks.slack.com/"
        return 1
    fi
    
    return 0
}

# Format Slack message with basic markdown
format_slack_message() {
    local message="$1"
    
    # Basic formatting improvements for Slack
    # Convert some common patterns to Slack markdown
    
    # Make command names monospace (if they contain common command patterns)
    message=$(echo "$message" | sed 's/\(Command: \)\(.*\)/\1`\2`/')
    
    # Make exit codes bold
    message=$(echo "$message" | sed 's/\(Exit [Cc]ode: \)\([0-9]\+\)/\1*\2*/')
    
    # Make hostname and user bold
    message=$(echo "$message" | sed 's/\(Hostname: \)\(.*\)/\1*\2*/')
    message=$(echo "$message" | sed 's/\(User: \)\(.*\)/\1*\2*/')
    
    echo "$message"
}

# Get Slack channel info (if webhook supports it)
get_slack_channel_info() {
    # This is a basic function that could be extended
    # Currently just validates that the webhook is accessible
    
    if [[ -z "$MOE_slack_webhook_url" ]]; then
        return 1
    fi
    
    # Simple connectivity test
    local test_code
    test_code=$(curl -w "%{http_code}" -s -o /dev/null \
        -X POST \
        -H "Content-Type: application/json" \
        -d '{"text": ""}' \
        "$MOE_slack_webhook_url")
    
    case "$test_code" in
        200|400) # 400 is expected for empty message, but shows webhook works
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}