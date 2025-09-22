#!/bin/bash

# templates.sh - Template rendering functions for mailonerror

# Escape special characters for JSON
json_escape() {
    local text="$1"
    # Escape backslashes, double quotes, newlines, tabs, carriage returns
    text=${text//\\/\\\\}
    text=${text//\"/\\\"}
    text=${text//$'\n'/\\n}
    text=${text//$'\t'/\\t}
    text=${text//$'\r'/\\r}
    echo "$text"
}

# Escape special characters for HTML
html_escape() {
    local text="$1"
    text=${text//&/&amp;}
    text=${text//</&lt;}
    text=${text//>/&gt;}
    text=${text//\"/&quot;}
    text=${text//\'/&#39;}
    echo "$text"
}

# Perform variable substitution on text
substitute_variables() {
    local text="$1"
    local escape_mode="${2:-none}"  # none, html, json
    
    # Prepare variables based on escape mode
    local cmd_var="$MOE_COMMAND"
    local exit_var="$MOE_EXIT_CODE"
    local stdout_var="$MOE_STDOUT_OUTPUT"
    local stderr_var="$MOE_STDERR_OUTPUT"
    local timestamp_var="$MOE_TIMESTAMP"
    local hostname_var="$HOSTNAME"
    local user_var="$USER"
    
    # Apply escaping if needed
    if [[ "$escape_mode" == "html" ]]; then
        cmd_var=$(html_escape "$cmd_var")
        stdout_var=$(html_escape "$stdout_var")
        stderr_var=$(html_escape "$stderr_var")
        timestamp_var=$(html_escape "$timestamp_var")
        hostname_var=$(html_escape "$hostname_var")
        user_var=$(html_escape "$user_var")
    elif [[ "$escape_mode" == "json" ]]; then
        cmd_var=$(json_escape "$cmd_var")
        stdout_var=$(json_escape "$stdout_var")
        stderr_var=$(json_escape "$stderr_var")
        timestamp_var=$(json_escape "$timestamp_var")
        hostname_var=$(json_escape "$hostname_var")
        user_var=$(json_escape "$user_var")
    fi
    
    # Perform substitutions
    text=${text//\$\{COMMAND\}/$cmd_var}
    text=${text//\$\{EXIT_CODE\}/$exit_var}
    text=${text//\$\{STDOUT\}/$stdout_var}
    text=${text//\$\{STDERR\}/$stderr_var}
    text=${text//\$\{TIMESTAMP\}/$timestamp_var}
    text=${text//\$\{HOSTNAME\}/$hostname_var}
    text=${text//\$\{USER\}/$user_var}
    
    echo "$text"
}

# Render email subject
render_subject() {
    local subject_text="$MOE_subject"
    
    # If subject is empty, use default
    if [[ -z "$subject_text" ]]; then
        subject_text="Command '\${COMMAND}' failed on \${HOSTNAME}"
    fi
    
    log_verbose "Rendering subject template"
    substitute_variables "$subject_text"
}

# Render HTML email body
render_html_body() {
    local html_content
    
    # Set default template file if not specified
    set_default_templates
    
    # Read HTML template file
    if [[ -f "$MOE_html_body_file" ]]; then
        log_verbose "Reading HTML template from: $MOE_html_body_file"
        html_content=$(cat "$MOE_html_body_file")
    else
        log_verbose "Using built-in default HTML template"
        # Built-in default HTML template
        html_content='<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Command Failure Notification</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { color: #d9534f; border-bottom: 2px solid #d9534f; padding-bottom: 10px; }
        .info { background-color: #f5f5f5; padding: 15px; margin: 10px 0; border-radius: 4px; }
        .output { background-color: #f8f8f8; border: 1px solid #ddd; padding: 10px; margin: 10px 0; border-radius: 4px; font-family: monospace; white-space: pre-wrap; }
        .label { font-weight: bold; }
    </style>
</head>
<body>
    <div class="header">
        <h2>Command Failure Notification</h2>
    </div>
    
    <div class="info">
        <p><span class="label">Command:</span> ${COMMAND}</p>
        <p><span class="label">Exit Code:</span> ${EXIT_CODE}</p>
        <p><span class="label">Timestamp:</span> ${TIMESTAMP}</p>
        <p><span class="label">Hostname:</span> ${HOSTNAME}</p>
        <p><span class="label">User:</span> ${USER}</p>
    </div>
    
    <h3>Standard Output (stdout):</h3>
    <div class="output">${STDOUT}</div>
    
    <h3>Standard Error (stderr):</h3>
    <div class="output">${STDERR}</div>
    
    <hr>
    <p><small>This notification was sent by mailonerror.</small></p>
</body>
</html>'
    fi
    
    log_verbose "Rendering HTML body template"
    substitute_variables "$html_content" "html"
}

# Render Slack message
render_slack_message() {
    local slack_content
    
    # Only render if Slack is configured
    if [[ -z "$MOE_slack_webhook_url" ]]; then
        log_verbose "Slack webhook not configured, skipping message rendering"
        return 0
    fi
    
    # Set default template file if not specified
    set_default_templates
    
    # Read Slack template file
    if [[ -f "$MOE_slack_message_file" ]]; then
        log_verbose "Reading Slack template from: $MOE_slack_message_file"
        slack_content=$(cat "$MOE_slack_message_file")
    else
        log_verbose "Using built-in default Slack template"
        # Built-in default Slack template
        slack_content='🚨 Command Failed on ${HOSTNAME}

*Command:* `${COMMAND}`
*Exit Code:* ${EXIT_CODE}
*User:* ${USER}
*Timestamp:* ${TIMESTAMP}

*stdout:*
```
${STDOUT}
```

*stderr:*
```
${STDERR}
```'
    fi
    
    log_verbose "Rendering Slack message template"
    substitute_variables "$slack_content"
}

# Create JSON payload for SendGrid email
create_sendgrid_payload() {
    local subject_rendered html_body_rendered
    
    subject_rendered=$(render_subject)
    html_body_rendered=$(render_html_body)
    
    # Escape content for JSON
    subject_rendered=$(json_escape "$subject_rendered")
    html_body_rendered=$(json_escape "$html_body_rendered")
    
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
            "subject": "$subject_rendered"
        }
    ],
    "from": $from_object,
    "content": [
        {
            "type": "text/html",
            "value": "$html_body_rendered"
        }
    ]
}
EOF
}

# Create JSON payload for Slack webhook
create_slack_payload() {
    local slack_message_rendered
    
    slack_message_rendered=$(render_slack_message)
    slack_message_rendered=$(json_escape "$slack_message_rendered")
    
    # Create the JSON payload
    cat << EOF
{
    "text": "$slack_message_rendered"
}
EOF
}

# Test template rendering with sample data
test_template_rendering() {
    echo "=== Template Rendering Test ==="
    
    # Set test data
    MOE_COMMAND="test-command --flag value"
    MOE_EXIT_CODE=1
    MOE_STDOUT_OUTPUT="This is test stdout output
with multiple lines
and special characters: <>&\"'"
    MOE_STDERR_OUTPUT="This is test stderr output
Error: Something went wrong!"
    MOE_TIMESTAMP=$(date -Iseconds)
    
    echo "Test Variables:"
    echo "  COMMAND: $MOE_COMMAND"
    echo "  EXIT_CODE: $MOE_EXIT_CODE"
    echo "  HOSTNAME: $HOSTNAME"
    echo "  USER: $USER"
    echo "  TIMESTAMP: $MOE_TIMESTAMP"
    echo
    
    echo "Rendered Subject:"
    render_subject
    echo
    
    echo "Rendered HTML Body (first 20 lines):"
    render_html_body | head -20
    echo "..."
    echo
    
    if [[ -n "$MOE_slack_webhook_url" ]]; then
        echo "Rendered Slack Message:"
        render_slack_message
        echo
    fi
    
    echo "SendGrid JSON Payload (first 20 lines):"
    create_sendgrid_payload | head -20
    echo "..."
    echo
    
    if [[ -n "$MOE_slack_webhook_url" ]]; then
        echo "Slack JSON Payload:"
        create_slack_payload
        echo
    fi
    
    echo "Template rendering test completed."
}