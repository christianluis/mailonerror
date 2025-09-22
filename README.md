# mailonerror

A minimal command-line utility that wraps shell commands and sends HTML-formatted email notifications via SendGrid when they fail. Optionally sends Slack notifications as well.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-brightgreen.svg)](https://www.gnu.org/software/bash/)

## Features

- **Error Detection**: Automatically detects non-zero exit codes from wrapped commands
- **Email Notifications**: Sends professional HTML-formatted emails via SendGrid API
- **Slack Integration**: Optional Slack webhook notifications
- **Template System**: Customizable email and Slack message templates with variable substitution
- **Retry Logic**: Configurable retry with exponential backoff for email delivery
- **Multiple Usage Modes**: Pipe commands, wrap commands, or use with `&&`/`||`
- **Dry Run & Testing**: Built-in testing and simulation modes
- **Easy Installation**: Simple installer script for system-wide or user installation

## Quick Start

### Installation

```bash
# Install for current user
curl -fsSL https://raw.githubusercontent.com/christianluis/mailonerror/main/install.sh | bash -s -- --user --create-config

# Or clone and install from source
git clone https://github.com/christianluis/mailonerror.git
cd mailonerror
bash install.sh --user --create-config
```

### Configuration

Edit `~/.mailonerror/config`:

```bash
# SendGrid configuration (required)
sendgrid_api_key="SG.your_sendgrid_api_key_here"

# Email settings (required)
from_name="Mail on Error"
from="mailonerror@example.com"
to="admin@example.com"

# Optional Slack integration
slack_webhook_url="https://hooks.slack.com/services/XXX/YYY/ZZZ"
```

### Usage Examples

```bash
# Wrap a command that might fail
mailonerror -- backup.sh /important/data

# Pipe a command's output
some_long_running_process | mailonerror --verbose

# Use with shell operators
critical_task && echo "Success" || mailonerror

# Test your configuration
mailonerror --self-test

# Dry run to see what would be sent
mailonerror --dry-run -- ls /nonexistent
```

## Installation

### Quick Install

**For current user:**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/christianluis/mailonerror/main/install.sh) --user --create-config
```

**System-wide (requires sudo):**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/christianluis/mailonerror/main/install.sh) --system
```

### Manual Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/christianluis/mailonerror.git
   cd mailonerror
   ```

2. **Install:**
   ```bash
   # For current user
   bash install.sh --user
   
   # System-wide (requires sudo)
   sudo bash install.sh --system
   ```

3. **Create configuration:**
   ```bash
   bash install.sh --user --create-config
   ```

### Installation Options

```bash
# Available installer options
bash install.sh --help

Options:
  --system            Install system-wide (requires root)
  --user              Install for current user only
  --force             Overwrite existing installation
  --create-config     Create default configuration file
  --verbose           Enable verbose output
  --help              Show help message
```

### Installation Paths

**User Installation (`--user`):**
- Executable: `~/.local/bin/mailonerror`
- Libraries: `~/.local/share/mailonerror/lib/`
- Templates: `~/.local/share/mailonerror/templates/`
- Configuration: `~/.mailonerror/config`

**System Installation (`--system`):**
- Executable: `/usr/local/bin/mailonerror`
- Libraries: `/usr/local/share/mailonerror/lib/`
- Templates: `/usr/local/share/mailonerror/templates/`
- Configuration: `~/.mailonerror/config` (per-user)

The installation follows standard Unix filesystem hierarchy conventions, placing executables in `bin/`, shared data in `share/mailonerror/`, and user configuration in the home directory.

## Configuration

### Default Configuration File

The default configuration file is located at `~/.mailonerror/config`:

```bash
# SendGrid configuration (required)
sendgrid_api_key="SG.your_sendgrid_api_key_here"

# Email settings (required)
from_name="System Alerts"
from="alerts@your-domain.com"
to="admin@your-domain.com"

# Email subject template (optional)
subject="Command '\${COMMAND}' failed on \${HOSTNAME}"

# HTML body template file (optional)
html_body_file="~/.mailonerror/templates/default.html"

# Retry settings
retry_interval_seconds=10
max_retry_seconds=300

# Slack integration (optional)
slack_webhook_url="https://hooks.slack.com/services/XXX/YYY/ZZZ"
slack_message_file="~/.mailonerror/templates/slack.txt"
```

### Configuration Options

| Option | Required | Description |
|--------|----------|-------------|
| `sendgrid_api_key` | Yes | Your SendGrid API key |
| `from` | Yes | Sender email address |
| `to` | Yes | Recipient email address |
| `from_name` | No | Sender display name |
| `subject` | No | Email subject template |
| `html_body_file` | No | Path to HTML email template |
| `retry_interval_seconds` | No | Initial retry interval (default: 10) |
| `max_retry_seconds` | No | Maximum retry timeout (default: 300) |
| `slack_webhook_url` | No | Slack webhook URL for notifications |
| `slack_message_file` | No | Path to Slack message template |

## Usage

### Command Line Options

```bash
mailonerror [OPTIONS] [-- command [args...]]

Options:
  --config FILE           Use alternative config file
  --from EMAIL            Override sender address
  --to EMAIL              Override recipient address
  --subject TEXT          Override subject template
  --html-body FILE        Path to HTML body template
  --sendgrid-key KEY      Override SendGrid API key
  --slack-webhook URL     Slack webhook URL
  --slack-message FILE    Slack message template
  --dry-run               Simulate behavior without sending
  --self-test             Send test email and Slack message
  --retry                 Enable retry loop for email delivery
  --verbose               Enable debug output
  --help                  Show help message
```

### Usage Modes

**1. Command Wrapper Mode**
```bash
mailonerror -- command arg1 arg2
```

**2. Pipeline Mode**
```bash
command | mailonerror
```

**3. Conditional Mode**
```bash
command && echo ok || mailonerror
```

**4. Testing Modes**
```bash
# Test configuration and send test messages
mailonerror --self-test

# Dry run - show what would be sent without sending
mailonerror --dry-run -- failing-command
```

### Examples

**Monitor a backup script:**
```bash
mailonerror -- /usr/local/bin/backup.sh
```

**Monitor a long-running process with verbose output:**
```bash
/usr/local/bin/data-processing.sh | mailonerror --verbose
```

**Monitor with custom configuration:**
```bash
mailonerror --config /etc/mailonerror/production.conf --retry -- critical-task.sh
```

**Override email settings:**
```bash
mailonerror --from "backup@company.com" --to "ops@company.com" -- backup.sh
```

## Template System

### Template Variables

All templates support the following variables:

- `${COMMAND}` - Full command string
- `${EXIT_CODE}` - Exit code (integer)
- `${STDOUT}` - Captured stdout
- `${STDERR}` - Captured stderr
- `${TIMESTAMP}` - ISO 8601 timestamp
- `${HOSTNAME}` - System hostname
- `${USER}` - User running mailonerror

### Email Templates

**Default HTML Template**
The built-in HTML template creates professional-looking email notifications with:
- Responsive design that works on mobile and desktop
- Syntax highlighting for command output
- Color-coded sections for different types of information
- Clean typography and proper spacing

**Custom HTML Template Example:**
```html
<!DOCTYPE html>
<html>
<body>
    <h1>🚨 Command Failed</h1>
    <p><strong>Command:</strong> <code>${COMMAND}</code></p>
    <p><strong>Exit Code:</strong> ${EXIT_CODE}</p>
    <p><strong>Host:</strong> ${HOSTNAME}</p>
    <p><strong>Time:</strong> ${TIMESTAMP}</p>
    
    <h2>Output</h2>
    <pre>${STDOUT}</pre>
    
    <h2>Errors</h2>
    <pre>${STDERR}</pre>
</body>
</html>
```

### Slack Templates

**Default Slack Template:**
```text
🚨 *Command Failed on ${HOSTNAME}*

*Command:* `${COMMAND}`
*Exit Code:* ${EXIT_CODE}
*User:* ${USER}
*Timestamp:* ${TIMESTAMP}

*📤 stdout:*
```
${STDOUT}
```

*🚨 stderr:*
```
${STDERR}
```
```

**Custom Slack Template Example:**
```text
⚠️ Alert from ${HOSTNAME}

Command `${COMMAND}` failed with exit code ${EXIT_CODE}
Time: ${TIMESTAMP}
User: ${USER}

Check the logs for details.
```

## Advanced Usage

### Retry Configuration

Enable retry with exponential backoff:

```bash
# Enable retry in config file
retry_interval_seconds=10
max_retry_seconds=300

# Or use command line option
mailonerror --retry -- unreliable-command
```

### Custom Configuration Files

```bash
# Use a different config file
mailonerror --config /path/to/custom.conf -- command

# Production vs staging configurations
mailonerror --config ~/.mailonerror/staging.conf -- deploy-staging.sh
mailonerror --config ~/.mailonerror/production.conf -- deploy-production.sh
```

### Integration with Cron

```bash
# Add to crontab
0 2 * * * mailonerror --config /etc/mailonerror/backup.conf -- /usr/local/bin/nightly-backup.sh
30 1 * * 0 mailonerror --retry -- /usr/local/bin/weekly-maintenance.sh
```

### Integration with Systemd

Create a systemd service that uses mailonerror:

```ini
[Unit]
Description=Critical Task with Email Notifications
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mailonerror --config /etc/mailonerror/critical.conf -- /usr/local/bin/critical-task.sh
User=nobody
Group=nobody

[Install]
WantedBy=multi-user.target
```

### Log Monitoring

Monitor log files for errors:

```bash
# Monitor Apache error log
tail -f /var/log/apache2/error.log | grep "ERROR" | mailonerror --subject "Apache Error Detected"

# Monitor application logs
journalctl -u myapp.service -f | grep -i "fatal\|error" | mailonerror
```

## Testing

### Run Tests

The project includes comprehensive test suites:

```bash
# Run all tests
bash tests/test_config.sh
bash tests/test_templates.sh
bash tests/test_retry.sh

# Run with verbose output
VERBOSE=true bash tests/test_config.sh
```

### Test Coverage

- **Config Tests**: Configuration parsing, validation, overrides
- **Template Tests**: Variable substitution, HTML/JSON escaping, template rendering
- **Retry Tests**: Email delivery, retry logic, HTTP response handling

### Self-Test Feature

Use the built-in self-test to verify your configuration:

```bash
# Test configuration and connectivity
mailonerror --self-test

# Test with verbose output
mailonerror --self-test --verbose
```

## Troubleshooting

### Common Issues

**1. SendGrid API Key Issues**
```bash
# Test API key
curl -H "Authorization: Bearer SG.your_key_here" https://api.sendgrid.com/v3/user/profile
```

**2. Email Not Received**
- Check spam/junk folder
- Verify sender and recipient email addresses
- Ensure SendGrid sender identity is verified
- Use `--self-test` to send a test email

**3. Slack Notifications Not Working**
- Verify webhook URL is correct
- Test webhook manually:
  ```bash
  curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"Test message"}' \
    YOUR_SLACK_WEBHOOK_URL
  ```

**4. Permission Issues**
- Ensure mailonerror is executable: `chmod +x /path/to/mailonerror`
- Check config file permissions: `chmod 600 ~/.mailonerror/config`

### Debug Mode

Enable verbose output for troubleshooting:

```bash
# Verbose mode shows detailed execution information
mailonerror --verbose -- command

# Dry run shows what would be sent
mailonerror --dry-run --verbose -- command
```

### Log Files

mailonerror doesn't create log files by default, but you can redirect output:

```bash
# Log to file
mailonerror --verbose -- command 2>> /var/log/mailonerror.log

# Log with timestamps
mailonerror --verbose -- command 2>&1 | while read line; do echo "$(date): $line"; done >> /var/log/mailonerror.log
```

## Security Considerations

### API Key Security

- Store API keys in configuration files with restricted permissions:
  ```bash
  chmod 600 ~/.mailonerror/config
  ```
- Use environment variables for sensitive deployments:
  ```bash
  export SENDGRID_API_KEY="SG.your_key_here"
  mailonerror --sendgrid-key "$SENDGRID_API_KEY" -- command
  ```

### Network Security

- mailonerror makes HTTPS requests to SendGrid and Slack
- No sensitive data is logged in verbose mode (API keys are redacted)
- Template output may contain sensitive command output - review templates carefully

### File Permissions

Recommended permissions:
```bash
chmod 755 /usr/local/bin/mailonerror          # Executable
chmod 600 ~/.mailonerror/config               # Config file
chmod 644 ~/.mailonerror/templates/*.html     # Templates
```

## Contributing

### Development Setup

1. Clone the repository
2. Make changes to the source code
3. Run tests: `bash tests/test_*.sh`
4. Test installation: `bash install.sh --user --force`

### Adding Features

- Add new configuration options in `lib/config.sh`
- Add new template functions in `lib/templates.sh`
- Add tests for new functionality
- Update documentation

### Project Structure

```
mailonerror/
├── mailonerror             # Main executable script
├── install.sh              # Installation script
├── lib/                    # Library modules
│   ├── config.sh          # Configuration parsing
│   ├── mailer.sh          # SendGrid integration
│   ├── slack.sh           # Slack integration
│   └── templates.sh       # Template rendering
├── templates/             # Default templates
│   ├── default.html       # HTML email template
│   └── slack.txt          # Slack message template
├── tests/                 # Test suites
│   ├── test_config.sh     # Configuration tests
│   ├── test_templates.sh  # Template tests
│   └── test_retry.sh      # Retry/email tests
└── README.md              # This file
```

## License

MIT License - see LICENSE file for details.

## Changelog

### Version 0.0.1
- Initial release
- SendGrid email integration
- Slack webhook support
- Template system with variable substitution
- Retry logic with exponential backoff
- Comprehensive test suite
- Installation script
- Full documentation

## Support

- GitHub Issues: https://github.com/christianluis/mailonerror/issues
- Documentation: https://github.com/christianluis/mailonerror
- SendGrid Documentation: https://docs.sendgrid.com/
- Slack Webhooks: https://api.slack.com/messaging/webhooks