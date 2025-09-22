#!/bin/bash

# mailonerror.sh - Installation script for mailonerror
# This script can be used to install mailonerror system-wide or in a user directory

set -euo pipefail

# Version information
VERSION="0.0.1"
GITHUB_REPO="user/mailonerror"  # Update with actual repository
INSTALL_PREFIX="/usr/local"
USER_PREFIX="$HOME/.local"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SYSTEM_INSTALL=false
USER_INSTALL=false
FORCE_INSTALL=false
CREATE_CONFIG=false
VERBOSE=false

# Print colored output
print_color() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

print_info() {
    print_color "$BLUE" "[INFO] $*"
}

print_success() {
    print_color "$GREEN" "[SUCCESS] $*"
}

print_warning() {
    print_color "$YELLOW" "[WARNING] $*"
}

print_error() {
    print_color "$RED" "[ERROR] $*" >&2
}

print_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        print_color "$BLUE" "[VERBOSE] $*"
    fi
}

# Show usage information
usage() {
    cat << EOF
mailonerror installer - v${VERSION}

USAGE:
    bash install.sh [OPTIONS]

OPTIONS:
    --system            Install system-wide (requires root, installs to $INSTALL_PREFIX)
    --user              Install for current user only (installs to $USER_PREFIX)
    --force             Overwrite existing installation
    --create-config     Create default configuration file
    --verbose           Enable verbose output
    --help              Show this help message

EXAMPLES:
    # Install for current user
    bash install.sh --user

    # Install system-wide (requires sudo)
    sudo bash install.sh --system

    # Install with configuration file creation
    bash install.sh --user --create-config

    # Force reinstall
    bash install.sh --user --force

INSTALLATION PATHS:
    System install: $INSTALL_PREFIX/bin/mailonerror
    User install:   $USER_PREFIX/bin/mailonerror
    Config file:    ~/.mailonerror/config

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --system)
                SYSTEM_INSTALL=true
                shift
                ;;
            --user)
                USER_INSTALL=true
                shift
                ;;
            --force)
                FORCE_INSTALL=true
                shift
                ;;
            --create-config)
                CREATE_CONFIG=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Detect if we're running from a source directory or as a standalone script
detect_installation_source() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Check if we're in a source directory with the expected structure
    if [[ -f "$script_dir/mailonerror" && -d "$script_dir/lib" && -d "$script_dir/templates" ]]; then
        print_verbose "Installing from source directory: $script_dir"
        SOURCE_DIR="$script_dir"
        INSTALL_MODE="source"
    else
        print_verbose "Running as standalone installer"
        INSTALL_MODE="download"
    fi
}

# Create directory if it doesn't exist
ensure_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        print_verbose "Creating directory: $dir"
        mkdir -p "$dir"
    fi
}

# Install from source directory
install_from_source() {
    local install_dir="$1"
    local bin_dir="$install_dir/bin"
    local share_dir="$install_dir/share/mailonerror"
    
    ensure_directory "$bin_dir"
    ensure_directory "$share_dir"
    
    print_info "Installing mailonerror from source..."
    
    # Copy main script
    print_verbose "Copying main script to $bin_dir/mailonerror"
    cp "$SOURCE_DIR/mailonerror" "$bin_dir/mailonerror"
    chmod +x "$bin_dir/mailonerror"
    
    # Copy lib directory
    print_verbose "Copying lib directory to $share_dir/"
    cp -r "$SOURCE_DIR/lib" "$share_dir/"
    
    # Copy templates directory
    print_verbose "Copying templates directory to $share_dir/"
    cp -r "$SOURCE_DIR/templates" "$share_dir/"
    
    # No need to update script paths - the script auto-detects lib and template directories
    
    print_success "Installed mailonerror to $bin_dir/mailonerror"
}

# Download and install from GitHub (placeholder - would need actual implementation)
install_from_download() {
    local install_dir="$1"
    
    print_error "Download installation not yet implemented"
    print_info "Please clone the repository and run the installer from the source directory"
    exit 1
}

# Create default configuration file
create_default_config() {
    local config_dir="$HOME/.mailonerror"
    local config_file="$config_dir/config"
    local templates_dir="$config_dir/templates"
    
    if [[ -f "$config_file" && "$FORCE_INSTALL" != "true" ]]; then
        print_warning "Configuration file already exists: $config_file"
        print_info "Use --force to overwrite existing configuration"
        return 0
    fi
    
    print_info "Creating default configuration..."
    
    ensure_directory "$config_dir"
    ensure_directory "$templates_dir"
    
    # Create default config file
    cat > "$config_file" << 'EOF'
# mailonerror configuration file
# Copy this file to ~/.mailonerror/config and customize as needed

# SendGrid configuration (required)
sendgrid_api_key="SG.your_sendgrid_api_key_here"

# Email settings (required)
from_name="Mail on Error"
from="mailonerror@example.com"
to="admin@example.com"

# Email subject template (optional, uses default if not specified)
subject="Command '\${COMMAND}' failed on \${HOSTNAME}"

# HTML body template file (optional, uses built-in template if not specified)
# html_body_file="~/.mailonerror/templates/custom.html"

# Retry settings
retry_interval_seconds=10
max_retry_seconds=300

# Slack integration (optional)
# slack_webhook_url="https://hooks.slack.com/services/XXX/YYY/ZZZ"
# slack_message_file="~/.mailonerror/templates/slack.txt"
EOF
    
    # Copy default templates if installing from source
    if [[ "$INSTALL_MODE" == "source" && -d "$SOURCE_DIR/templates" ]]; then
        print_verbose "Copying template files to $templates_dir/"
        cp "$SOURCE_DIR/templates/"* "$templates_dir/"
    fi
    
    print_success "Created configuration file: $config_file"
    print_info "Please edit the configuration file to add your SendGrid API key and email addresses"
}

# Check if mailonerror is already installed
check_existing_installation() {
    local install_dir="$1"
    local bin_path="$install_dir/bin/mailonerror"
    
    if [[ -f "$bin_path" ]]; then
        if [[ "$FORCE_INSTALL" == "true" ]]; then
            print_warning "Overwriting existing installation at $bin_path"
            return 0
        else
            print_error "mailonerror is already installed at $bin_path"
            print_info "Use --force to overwrite the existing installation"
            exit 1
        fi
    fi
}

# Add directory to PATH if not already there
update_path() {
    local bin_dir="$1"
    local shell_rc=""
    
    # Determine which shell config file to update
    if [[ -n "${BASH_VERSION:-}" ]]; then
        if [[ -f "$HOME/.bashrc" ]]; then
            shell_rc="$HOME/.bashrc"
        elif [[ -f "$HOME/.bash_profile" ]]; then
            shell_rc="$HOME/.bash_profile"
        fi
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        shell_rc="$HOME/.zshrc"
    fi
    
    # Check if bin_dir is already in PATH
    if [[ ":$PATH:" == *":$bin_dir:"* ]]; then
        print_verbose "Directory $bin_dir is already in PATH"
        return 0
    fi
    
    if [[ -n "$shell_rc" && "$USER_INSTALL" == "true" ]]; then
        print_info "Adding $bin_dir to PATH in $shell_rc"
        echo "" >> "$shell_rc"
        echo "# Added by mailonerror installer" >> "$shell_rc"
        echo "export PATH=\"$bin_dir:\$PATH\"" >> "$shell_rc"
        print_info "Please restart your shell or run: source $shell_rc"
    else
        print_info "Please add $bin_dir to your PATH environment variable"
    fi
}

# Verify installation
verify_installation() {
    local install_dir="$1"
    local bin_path="$install_dir/bin/mailonerror"
    
    print_info "Verifying installation..."
    
    if [[ -f "$bin_path" && -x "$bin_path" ]]; then
        print_success "mailonerror executable is installed and executable"
        
        # Test help command
        if "$bin_path" --help >/dev/null 2>&1; then
            print_success "mailonerror help command works"
        else
            print_warning "mailonerror help command failed - installation may be incomplete"
        fi
    else
        print_error "Installation verification failed"
        exit 1
    fi
}

# Main installation function
main() {
    print_info "mailonerror installer v${VERSION}"
    echo
    
    # Parse arguments
    parse_args "$@"
    
    # Validate arguments
    if [[ "$SYSTEM_INSTALL" == "true" && "$USER_INSTALL" == "true" ]]; then
        print_error "Cannot specify both --system and --user"
        exit 1
    fi
    
    if [[ "$SYSTEM_INSTALL" == "false" && "$USER_INSTALL" == "false" ]]; then
        print_error "Must specify either --system or --user installation"
        usage
        exit 1
    fi
    
    # Check permissions for system install
    if [[ "$SYSTEM_INSTALL" == "true" && $EUID -ne 0 ]]; then
        print_error "System installation requires root privileges"
        print_info "Try: sudo bash mailonerror.sh --system"
        exit 1
    fi
    
    # Determine installation directory
    local install_dir
    if [[ "$SYSTEM_INSTALL" == "true" ]]; then
        install_dir="$INSTALL_PREFIX"
        print_info "Installing system-wide to $install_dir"
    else
        install_dir="$USER_PREFIX"
        print_info "Installing for user to $install_dir"
    fi
    
    # Detect installation source
    detect_installation_source
    
    # Check for existing installation
    check_existing_installation "$install_dir"
    
    # Perform installation
    case "$INSTALL_MODE" in
        source)
            install_from_source "$install_dir"
            ;;
        download)
            install_from_download "$install_dir"
            ;;
    esac
    
    # Create configuration if requested
    if [[ "$CREATE_CONFIG" == "true" ]]; then
        create_default_config
    fi
    
    # Update PATH for user installations
    if [[ "$USER_INSTALL" == "true" ]]; then
        update_path "$install_dir/bin"
    fi
    
    # Verify installation
    verify_installation "$install_dir"
    
    echo
    print_success "mailonerror installation completed successfully!"
    
    # Show next steps
    echo
    print_info "Next steps:"
    if [[ "$CREATE_CONFIG" != "true" ]]; then
        echo "  1. Create configuration: mailonerror.sh --user --create-config"
    fi
    echo "  2. Edit ~/.mailonerror/config with your SendGrid API key and email settings"
    echo "  3. Test configuration: mailonerror --self-test"
    echo "  4. Test with a failing command: mailonerror -- ls /nonexistent"
    echo
    print_info "Documentation and examples: https://github.com/${GITHUB_REPO}"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi