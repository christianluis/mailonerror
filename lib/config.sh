#!/bin/bash

# config.sh - Configuration parsing functions for mailonerror

# Default configuration values
MOE_sendgrid_api_key=""
MOE_from_name="Mail on Error"
MOE_from=""
MOE_to=""
MOE_subject=""
MOE_html_body_file=""
MOE_retry_interval_seconds=10
MOE_max_retry_seconds=300
MOE_slack_webhook_url=""
MOE_slack_message_file=""

# Load configuration from file and apply overrides
load_config() {
    local config_file="${MOE_CONFIG_FILE:-$MOE_DEFAULT_CONFIG_FILE}"
    
    log_verbose "Loading configuration from: $config_file"
    
    # Load configuration file if it exists
    if [[ -f "$config_file" ]]; then
        # Source the config file in a safe way
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            
            # Remove quotes from value if present
            value=$(echo "$value" | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
            
            # Expand tilde in file paths
            if [[ "$value" =~ ^~/ ]]; then
                value="${HOME}/${value#~/}"
            fi
            
            # Set the variable
            case "$key" in
                sendgrid_api_key) MOE_sendgrid_api_key="$value" ;;
                from_name) MOE_from_name="$value" ;;
                from) MOE_from="$value" ;;
                to) MOE_to="$value" ;;
                subject) MOE_subject="$value" ;;
                html_body_file) MOE_html_body_file="$value" ;;
                retry_interval_seconds) MOE_retry_interval_seconds="$value" ;;
                max_retry_seconds) MOE_max_retry_seconds="$value" ;;
                slack_webhook_url) MOE_slack_webhook_url="$value" ;;
                slack_message_file) MOE_slack_message_file="$value" ;;
                *)
                    log_verbose "Unknown config key: $key"
                    ;;
            esac
        done < <(grep -v '^[[:space:]]*#' "$config_file" | grep -v '^[[:space:]]*$')
        
        log_verbose "Configuration loaded successfully"
    else
        log_verbose "Config file not found: $config_file (using defaults)"
    fi
    
    # Apply command line overrides
    apply_overrides
    
    # Set default templates
    set_default_templates
    
    # Validate required configuration
    validate_config
}

# Apply command line overrides
apply_overrides() {
    if [[ -n "$MOE_OVERRIDE_FROM" ]]; then
        MOE_from="$MOE_OVERRIDE_FROM"
        log_verbose "Override: from=$MOE_from"
    fi
    
    if [[ -n "$MOE_OVERRIDE_TO" ]]; then
        MOE_to="$MOE_OVERRIDE_TO"
        log_verbose "Override: to=$MOE_to"
    fi
    
    if [[ -n "$MOE_OVERRIDE_SUBJECT" ]]; then
        MOE_subject="$MOE_OVERRIDE_SUBJECT"
        log_verbose "Override: subject=$MOE_subject"
    fi
    
    if [[ -n "$MOE_OVERRIDE_HTML_BODY_FILE" ]]; then
        MOE_html_body_file="$MOE_OVERRIDE_HTML_BODY_FILE"
        log_verbose "Override: html_body_file=$MOE_html_body_file"
    fi
    
    if [[ -n "$MOE_OVERRIDE_SENDGRID_KEY" ]]; then
        MOE_sendgrid_api_key="$MOE_OVERRIDE_SENDGRID_KEY"
        log_verbose "Override: sendgrid_api_key=<redacted>"
    fi
    
    if [[ -n "$MOE_OVERRIDE_SLACK_WEBHOOK" ]]; then
        MOE_slack_webhook_url="$MOE_OVERRIDE_SLACK_WEBHOOK"
        log_verbose "Override: slack_webhook_url=<redacted>"
    fi
    
    if [[ -n "$MOE_OVERRIDE_SLACK_MESSAGE_FILE" ]]; then
        MOE_slack_message_file="$MOE_OVERRIDE_SLACK_MESSAGE_FILE"
        log_verbose "Override: slack_message_file=$MOE_slack_message_file"
    fi
}

# Validate required configuration
validate_config() {
    local errors=()
    
    # Check required email configuration
    if [[ -z "$MOE_sendgrid_api_key" ]]; then
        errors+=("SendGrid API key is required (sendgrid_api_key)")
    fi
    
    if [[ -z "$MOE_from" ]]; then
        errors+=("Sender email address is required (from)")
    fi
    
    if [[ -z "$MOE_to" ]]; then
        errors+=("Recipient email address is required (to)")
    fi
    
    # Validate email formats (basic validation)
    if [[ -n "$MOE_from" && ! "$MOE_from" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        errors+=("Invalid sender email format: $MOE_from")
    fi
    
    if [[ -n "$MOE_to" && ! "$MOE_to" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        errors+=("Invalid recipient email format: $MOE_to")
    fi
    
    # Validate numeric values
    if [[ ! "$MOE_retry_interval_seconds" =~ ^[0-9]+$ ]]; then
        errors+=("retry_interval_seconds must be a positive integer")
    fi
    
    if [[ ! "$MOE_max_retry_seconds" =~ ^[0-9]+$ ]]; then
        errors+=("max_retry_seconds must be a positive integer")
    fi
    
    # Check if HTML body file exists if specified
    if [[ -n "$MOE_html_body_file" && ! -f "$MOE_html_body_file" ]]; then
        errors+=("HTML body template file not found: $MOE_html_body_file")
    fi
    
    # Check if Slack message file exists if specified
    if [[ -n "$MOE_slack_message_file" && ! -f "$MOE_slack_message_file" ]]; then
        errors+=("Slack message template file not found: $MOE_slack_message_file")
    fi
    
    # Report validation errors
    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Configuration validation failed:"
        for error in "${errors[@]}"; do
            log_error "  - $error"
        done
        
        if [[ "$MOE_DRY_RUN" != "true" && "$MOE_SELF_TEST" != "true" ]]; then
            exit 1
        fi
    fi
}

# Set default template files if not specified
set_default_templates() {
    # Set default subject if not specified
    if [[ -z "$MOE_subject" ]]; then
        MOE_subject="Command '\${COMMAND}' failed on \${HOSTNAME}"
    fi
    
    # Set default HTML body file if not specified
    if [[ -z "$MOE_html_body_file" ]]; then
        MOE_html_body_file="${MOE_TEMPLATES_DIR}/default.html"
    fi
    
    # Set default Slack message file if not specified and Slack is configured
    if [[ -z "$MOE_slack_message_file" && -n "$MOE_slack_webhook_url" ]]; then
        MOE_slack_message_file="${MOE_TEMPLATES_DIR}/slack.txt"
    fi
}

# Print current configuration (for debugging)
print_config() {
    echo "Current Configuration:"
    echo "  sendgrid_api_key: ${MOE_sendgrid_api_key:+<set>}${MOE_sendgrid_api_key:-<not set>}"
    echo "  from_name: ${MOE_from_name:-<not set>}"
    echo "  from: ${MOE_from:-<not set>}"
    echo "  to: ${MOE_to:-<not set>}"
    echo "  subject: ${MOE_subject:-<not set>}"
    echo "  html_body_file: ${MOE_html_body_file:-<not set>}"
    echo "  retry_interval_seconds: $MOE_retry_interval_seconds"
    echo "  max_retry_seconds: $MOE_max_retry_seconds"
    echo "  slack_webhook_url: ${MOE_slack_webhook_url:+<set>}${MOE_slack_webhook_url:-<not set>}"
    echo "  slack_message_file: ${MOE_slack_message_file:-<not set>}"
}