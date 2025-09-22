#!/bin/bash

# mailer.sh - SendGrid API functions with retry logic for mailonerror

# Send email via SendGrid API
send_email() {
    log_verbose "Preparing to send email notification"
    
    # Validate required configuration
    if [[ -z "$MOE_sendgrid_api_key" ]]; then
        log_error "SendGrid API key not configured"
        return 1
    fi
    
    if [[ -z "$MOE_from" || -z "$MOE_to" ]]; then
        log_error "Email addresses not configured (from: '$MOE_from', to: '$MOE_to')"
        return 1
    fi
    
    # Create SendGrid payload
    local payload
    payload=$(create_sendgrid_payload)
    
    if [[ -z "$payload" ]]; then
        log_error "Failed to create SendGrid payload"
        return 1
    fi
    
    log_verbose "SendGrid payload created successfully"
    
    # Send email with or without retry
    if [[ "$MOE_RETRY_ENABLED" == "true" ]]; then
        send_email_with_retry "$payload"
    else
        send_email_once "$payload"
    fi
}

# Send email once (no retry)
send_email_once() {
    local payload="$1"
    local temp_response temp_headers
    temp_response=$(mktemp)
    temp_headers=$(mktemp)
    
    log_verbose "Sending email via SendGrid API (single attempt)"
    
    # Make the API request
    local http_code
    http_code=$(curl -w "%{http_code}" -s \
        -X POST \
        -H "Authorization: Bearer $MOE_sendgrid_api_key" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        -D "$temp_headers" \
        -o "$temp_response" \
        "https://api.sendgrid.com/v3/mail/send")
    
    local curl_exit_code=$?
    
    # Read response and headers
    local response_body response_headers
    response_body=$(cat "$temp_response" 2>/dev/null || echo "")
    response_headers=$(cat "$temp_headers" 2>/dev/null || echo "")
    
    # Cleanup temp files
    rm -f "$temp_response" "$temp_headers"
    
    # Check curl success
    if [[ $curl_exit_code -ne 0 ]]; then
        log_error "Curl failed with exit code $curl_exit_code"
        return 1
    fi
    
    # Log response details
    log_verbose "HTTP response code: $http_code"
    if [[ "$MOE_VERBOSE" == "true" && -n "$response_body" ]]; then
        log_verbose "Response body: $response_body"
    fi
    
    # Check for success (SendGrid returns 202 for accepted)
    if [[ "$http_code" == "202" ]]; then
        log_verbose "Email sent successfully"
        return 0
    else
        log_error "SendGrid API returned HTTP $http_code"
        if [[ -n "$response_body" ]]; then
            log_error "Response: $response_body"
        fi
        return 1
    fi
}

# Send email with retry logic
send_email_with_retry() {
    local payload="$1"
    local start_time attempt_count retry_interval
    
    start_time=$(date +%s)
    attempt_count=0
    retry_interval=$MOE_retry_interval_seconds
    
    log_verbose "Sending email with retry enabled (max_retry_seconds: $MOE_max_retry_seconds)"
    
    while true; do
        attempt_count=$((attempt_count + 1))
        local current_time elapsed_time
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        
        log_verbose "Email attempt #$attempt_count (elapsed: ${elapsed_time}s)"
        
        # Try to send the email
        if send_email_once "$payload"; then
            log_verbose "Email sent successfully on attempt #$attempt_count"
            return 0
        fi
        
        # Check if we've exceeded the timeout
        if [[ $elapsed_time -ge $MOE_max_retry_seconds ]]; then
            log_error "Email delivery failed: timeout after ${elapsed_time}s ($attempt_count attempts)"
            return 1
        fi
        
        # Calculate next retry interval with exponential backoff
        local next_retry_time=$((current_time + retry_interval))
        local max_retry_time=$((start_time + MOE_max_retry_seconds))
        
        # Don't retry if the next attempt would exceed the timeout
        if [[ $next_retry_time -gt $max_retry_time ]]; then
            log_error "Email delivery failed: would exceed timeout (${attempt_count} attempts)"
            return 1
        fi
        
        log_verbose "Retrying in ${retry_interval}s..."
        sleep "$retry_interval"
        
        # Exponential backoff with jitter (max 60 seconds)
        retry_interval=$((retry_interval * 2))
        if [[ $retry_interval -gt 60 ]]; then
            retry_interval=60
        fi
        
        # Add jitter (random 0-25% of interval)
        local jitter=$((RANDOM % (retry_interval / 4 + 1)))
        retry_interval=$((retry_interval + jitter))
    done
}

# Test SendGrid configuration and connectivity
test_sendgrid_config() {
    echo "=== SendGrid Configuration Test ==="
    
    # Check configuration
    echo "Configuration:"
    echo "  API Key: ${MOE_sendgrid_api_key:+<set (${#MOE_sendgrid_api_key} chars)>}${MOE_sendgrid_api_key:-<not set>}"
    echo "  From: ${MOE_from:-<not set>}"
    echo "  From Name: ${MOE_from_name:-<not set>}"
    echo "  To: ${MOE_to:-<not set>}"
    echo "  Retry Enabled: $MOE_RETRY_ENABLED"
    echo "  Retry Interval: ${MOE_retry_interval_seconds}s"
    echo "  Max Retry Time: ${MOE_max_retry_seconds}s"
    echo
    
    # Test API key format
    if [[ -n "$MOE_sendgrid_api_key" ]]; then
        if [[ "$MOE_sendgrid_api_key" =~ ^SG\. ]]; then
            echo "✓ API key format looks correct"
        else
            echo "⚠ API key format may be incorrect (should start with 'SG.')"
        fi
    else
        echo "✗ API key not configured"
        return 1
    fi
    
    # Test basic connectivity to SendGrid API
    echo
    echo "Testing connectivity to SendGrid API..."
    
    local test_response test_code
    test_code=$(curl -w "%{http_code}" -s -o /dev/null \
        -H "Authorization: Bearer $MOE_sendgrid_api_key" \
        -H "Content-Type: application/json" \
        "https://api.sendgrid.com/v3/user/profile")
    
    local curl_exit=$?
    
    if [[ $curl_exit -eq 0 ]]; then
        case "$test_code" in
            200)
                echo "✓ SendGrid API connectivity successful"
                ;;
            401)
                echo "✗ SendGrid API authentication failed (invalid API key)"
                return 1
                ;;
            403)
                echo "✗ SendGrid API access forbidden (check API key permissions)"
                return 1
                ;;
            *)
                echo "⚠ SendGrid API returned HTTP $test_code"
                ;;
        esac
    else
        echo "✗ Failed to connect to SendGrid API (curl exit code: $curl_exit)"
        return 1
    fi
    
    echo
    echo "SendGrid configuration test completed."
    return 0
}

# Create a simple test payload for testing
create_test_sendgrid_payload() {
    local test_subject test_html
    test_subject="mailonerror test email - $(date)"
    test_html="<h2>Test Email</h2><p>This is a test email sent by mailonerror at $(date -Iseconds).</p><p>If you receive this, the email configuration is working correctly.</p>"
    
    # Escape for JSON
    test_subject=$(json_escape "$test_subject")
    test_html=$(json_escape "$test_html")
    
    # Build from object
    local from_object
    if [[ -n "$MOE_from_name" ]]; then
        from_object="{\"email\":\"$MOE_from\",\"name\":\"$(json_escape "$MOE_from_name")\"}"
    else
        from_object="{\"email\":\"$MOE_from\"}"
    fi
    
    # Create the JSON payload
    cat << EOF
{
    "personalizations": [
        {
            "to": [
                {
                    "email": "$MOE_to"
                }
            ],
            "subject": "$test_subject"
        }
    ],
    "from": $from_object,
    "content": [
        {
            "type": "text/html",
            "value": "$test_html"
        }
    ]
}
EOF
}

# Send a test email
send_test_email() {
    log_verbose "Sending test email"
    
    local original_payload_func="create_sendgrid_payload"
    
    # Temporarily override payload creation for test
    create_sendgrid_payload() {
        create_test_sendgrid_payload
    }
    
    # Send the test email
    local result=0
    send_email || result=1
    
    # Restore original function
    create_sendgrid_payload() {
        $original_payload_func
    }
    
    return $result
}