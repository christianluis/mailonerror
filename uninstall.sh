#!/bin/bash

# uninstall_mailonerror.sh - Uninstaller for mailonerror
# Language: Bash 4.0+

set -euo pipefail

# Version
VERSION="0.0.1"

# Installation paths
INSTALL_PREFIX="/usr/local"
USER_PREFIX="$HOME/.local"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SYSTEM_UNINSTALL=false
USER_UNINSTALL=false
REMOVE_CONFIG=false
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
mailonerror uninstaller - v${VERSION}

USAGE:
    bash uninstall.sh [OPTIONS]

OPTIONS:
    --system            Uninstall system-wide installation (requires root)
    --user              Uninstall user installation
    --remove-config     Also remove configuration files and templates
    --verbose           Enable verbose output
    --help              Show this help message

EXAMPLES:
    # Uninstall user installation
    bash uninstall.sh --user

    # Uninstall system-wide (requires sudo)
    sudo bash uninstall.sh --system

    # Uninstall and remove config files
    bash uninstall.sh --user --remove-config

UNINSTALLATION PATHS:
    System install: $INSTALL_PREFIX/bin/mailonerror
    User install:   $USER_PREFIX/bin/mailonerror
    Config files:   ~/.mailonerror/

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --system)
                SYSTEM_UNINSTALL=true
                shift
                ;;
            --user)
                USER_UNINSTALL=true
                shift
                ;;
            --remove-config)
                REMOVE_CONFIG=true
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

# Detect existing installations
detect_installations() {
    local found_installations=false
    
    print_info "Detecting existing mailonerror installations..."
    
    # Check system installation
    if [[ -f "$INSTALL_PREFIX/bin/mailonerror" ]]; then
        print_info "Found system installation: $INSTALL_PREFIX/bin/mailonerror"
        found_installations=true
        
        if [[ "$SYSTEM_UNINSTALL" != "true" ]]; then
            print_warning "Use --system to uninstall system-wide installation"
        fi
    fi
    
    # Check user installation
    if [[ -f "$USER_PREFIX/bin/mailonerror" ]]; then
        print_info "Found user installation: $USER_PREFIX/bin/mailonerror"
        found_installations=true
        
        if [[ "$USER_UNINSTALL" != "true" ]]; then
            print_warning "Use --user to uninstall user installation"
        fi
    fi
    
    # Check config directory
    if [[ -d "$HOME/.mailonerror" ]]; then
        print_info "Found configuration directory: $HOME/.mailonerror"
        if [[ "$REMOVE_CONFIG" != "true" ]]; then
            print_warning "Use --remove-config to also remove configuration files"
        fi
    fi
    
    if [[ "$found_installations" != "true" ]]; then
        print_warning "No mailonerror installations found"
        return 1
    fi
    
    return 0
}

# Remove file or directory safely
safe_remove() {
    local path="$1"
    local description="$2"
    
    if [[ -e "$path" ]]; then
        print_verbose "Removing $description: $path"
        rm -rf "$path"
        print_success "Removed $description"
    else
        print_verbose "$description not found: $path"
    fi
}

# Uninstall system-wide installation
uninstall_system() {
    if [[ "$SYSTEM_UNINSTALL" != "true" ]]; then
        return 0
    fi
    
    # Check if running as root for system uninstall
    if [[ $EUID -ne 0 ]]; then
        print_error "System uninstall requires root privileges. Please run with sudo."
        exit 1
    fi
    
    print_info "Uninstalling system-wide mailonerror installation..."
    
    # Remove main executable
    safe_remove "$INSTALL_PREFIX/bin/mailonerror" "system executable"
    
    # Remove shared data directory
    safe_remove "$INSTALL_PREFIX/share/mailonerror" "system shared data"
    
    print_success "System-wide installation removed"
}

# Uninstall user installation
uninstall_user() {
    if [[ "$USER_UNINSTALL" != "true" ]]; then
        return 0
    fi
    
    print_info "Uninstalling user mailonerror installation..."
    
    # Remove main executable
    safe_remove "$USER_PREFIX/bin/mailonerror" "user executable"
    
    # Remove shared data directory
    safe_remove "$USER_PREFIX/share/mailonerror" "user shared data"
    
    print_success "User installation removed"
}

# Remove configuration files
remove_config() {
    if [[ "$REMOVE_CONFIG" != "true" ]]; then
        return 0
    fi
    
    print_info "Removing configuration files..."
    
    if [[ -d "$HOME/.mailonerror" ]]; then
        # List what will be removed
        print_verbose "Configuration directory contents:"
        if [[ "$VERBOSE" == "true" ]]; then
            find "$HOME/.mailonerror" -type f 2>/dev/null | sed 's/^/  /' || true
        fi
        
        # Ask for confirmation if not in verbose mode
        if [[ "$VERBOSE" != "true" ]]; then
            echo -n "Remove configuration directory $HOME/.mailonerror? [y/N]: "
            read -r response
            case "$response" in
                [yY]|[yY][eE][sS])
                    ;;
                *)
                    print_info "Keeping configuration files"
                    return 0
                    ;;
            esac
        fi
        
        safe_remove "$HOME/.mailonerror" "configuration directory"
    else
        print_verbose "Configuration directory not found: $HOME/.mailonerror"
    fi
}

# Check if mailonerror is in PATH and warn
check_path_cleanup() {
    print_info "Checking PATH cleanup..."
    
    if command -v mailonerror >/dev/null 2>&1; then
        local mailonerror_path
        mailonerror_path=$(command -v mailonerror)
        print_warning "mailonerror is still found in PATH: $mailonerror_path"
        print_warning "You may need to restart your shell or update your PATH"
    else
        print_success "mailonerror removed from PATH"
    fi
}

# Validate arguments
validate_args() {
    if [[ "$SYSTEM_UNINSTALL" != "true" && "$USER_UNINSTALL" != "true" ]]; then
        print_error "You must specify either --system or --user (or both)"
        usage
        exit 1
    fi
}

# Main execution function
main() {
    parse_args "$@"
    validate_args
    
    print_info "mailonerror uninstaller v${VERSION}"
    echo
    
    # Detect existing installations
    if ! detect_installations; then
        exit 0
    fi
    
    echo
    
    # Perform uninstallation
    uninstall_system
    uninstall_user
    remove_config
    
    echo
    check_path_cleanup
    
    echo
    print_success "Uninstallation completed successfully"
    
    if [[ "$REMOVE_CONFIG" != "true" && -d "$HOME/.mailonerror" ]]; then
        print_info "Configuration files preserved in $HOME/.mailonerror"
        print_info "Use --remove-config to remove them in future runs"
    fi
}

# Run main function with all arguments
main "$@"