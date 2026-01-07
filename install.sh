#!/usr/bin/env bash

# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (c) 2026 erffy
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://gnu.org/licenses>.

set -euo pipefail

# Installer version for tracking
INSTALLER_VERSION="1.0.0"

# Detect if running in pipe mode (stdin is not a terminal)
PIPE_MODE=false
if [[ ! -t 0 ]]; then
    PIPE_MODE=true
fi

# Colors for output (disabled in pipe mode for better logging)
if [[ "$PIPE_MODE" == false ]] && [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && tput setaf 1 >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    BOLD=$(tput bold)
    NC=$(tput sgr0)
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

# Configuration with validation
ZIX_URL="https://codeberg.org/erffy/zix/raw/branch/master/zix"
ZIG_HOME="${ZIG_HOME:-$HOME/.zig}"
BIN_DIR="${ZIX_BIN_DIR:-$HOME/.local/bin}"
ZIX_SCRIPT="$ZIG_HOME/zix"
ZIX_SYMLINK="$BIN_DIR/zix"

# Installation log
LOG_FILE="${ZIX_LOG:-/tmp/zix-install-$$.log}"
exec 19>"$LOG_FILE"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&19
}

info() {
    echo -e "${BLUE}==>${NC} ${BOLD}$*${NC}"
    log "INFO: $*"
}

success() {
    echo -e "${GREEN}✓${NC} $*"
    log "SUCCESS: $*"
}

warn() {
    echo -e "${YELLOW}!${NC} $*"
    log "WARN: $*"
}

error() {
    echo -e "${RED}✗${NC} $*" >&2
    log "ERROR: $*"
}

die() {
    error "$*"
    error "Installation failed. Check log: $LOG_FILE"
    exit 1
}

# Cleanup on exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        rm -f "$LOG_FILE" 2>/dev/null || true
    else
        error "Installation failed with exit code $exit_code"
        error "Log saved to: $LOG_FILE"
    fi
}
trap cleanup EXIT

# Signal handling
handle_interrupt() {
    echo
    error "Installation interrupted by user"
    exit 130
}
trap handle_interrupt INT TERM

print_banner() {
    cat << "EOF"
    ____            __     ____  ___
   /_  / _   ____ _/ /    / /  |/  /
    / /_| | / /  ' \/    / / /|_/ / 
   /___/|_|/ /_/_/_/ /\_/ /_/  /_/  
        |___/      \____/            

   Zig Version Manager Installer
EOF
    echo -e "   ${BOLD}Version: $INSTALLER_VERSION${NC}"
    echo
}

# Validate installation environment
validate_environment() {
    log "Validating environment..."
    
    # Check if running as root (not recommended)
    if [[ $EUID -eq 0 ]]; then
        warn "Running as root is not recommended"
        warn "zix should be installed per-user, not system-wide"
        
        if [[ "$PIPE_MODE" == true ]]; then
            # In pipe mode, default to cancelling root installation
            die "Installation cancelled: running as root in pipe mode. Run directly if needed."
        else
            echo -n "Continue anyway? [y/N] "
            read -r response
            [[ ! "$response" =~ ^[Yy]$ ]] && die "Installation cancelled"
        fi
    fi
    
    # Validate URLs
    if [[ ! "$ZIX_URL" =~ ^https?:// ]]; then
        die "Invalid ZIX_URL: must start with http:// or https://"
    fi
    
    # Check disk space (need at least 100MB)
    local available_space
    if command -v df >/dev/null 2>&1; then
        available_space=$(df -k "$HOME" 2>/dev/null | awk 'NR==2 {print $4}') || available_space=999999
        if [[ $available_space -lt 102400 ]]; then
            die "Insufficient disk space. Need at least 100MB free in $HOME"
        fi
    fi
    
    # Check write permissions
    if [[ ! -w "$HOME" ]]; then
        die "No write permission in $HOME directory"
    fi
    
    log "Environment validation passed"
}

# Check if command exists
has_command() {
    command -v "$1" >/dev/null 2>&1
}

# Detect downloader with fallback chain
detect_downloader() {
    local downloaders=("curl" "wget" "aria2c")
    
    for tool in "${downloaders[@]}"; do
        if has_command "$tool"; then
            echo "$tool"
            return 0
        fi
    done
    
    return 1
}

# Download file with retry logic
download_file() {
    local url="$1"
    local output="$2"
    local downloader="$3"
    local max_retries=3
    local retry_delay=2
    
    log "Downloading: $url -> $output (using $downloader)"
    
    for ((i=1; i<=max_retries; i++)); do
        if [[ $i -gt 1 ]]; then
            warn "Retry attempt $i/$max_retries..."
            sleep $retry_delay
        fi
        
        case "$downloader" in
            curl)
                if curl -fsSL --connect-timeout 10 --max-time 60 \
                    --retry 2 --retry-delay 2 \
                    -A "zix-installer/$INSTALLER_VERSION" \
                    "$url" -o "$output" >> "$LOG_FILE" 2>&1; then
                    log "Download successful"
                    return 0
                fi
                ;;
            wget)
                if wget -q --timeout=30 --tries=3 --waitretry=2 \
                    --user-agent="zix-installer/$INSTALLER_VERSION" \
                    -O "$output" "$url" >> "$LOG_FILE" 2>&1; then
                    log "Download successful"
                    return 0
                fi
                ;;
            aria2c)
                if aria2c --console-log-level=error --summary-interval=0 \
                    -x 4 -s 4 --max-tries=3 --retry-wait=2 \
                    --connect-timeout=10 --timeout=30 \
                    --user-agent="zix-installer/$INSTALLER_VERSION" \
                    --allow-overwrite=true \
                    --auto-file-renaming=false \
                    -d "$(dirname "$output")" -o "$(basename "$output")" \
                    "$url" >> "$LOG_FILE" 2>&1; then
                    log "Download successful"
                    return 0
                fi
                ;;
        esac
        
        log "Download attempt $i failed"
    done
    
    error "Failed to download after $max_retries attempts"
    return 1
}

# Verify downloaded script integrity
verify_script() {
    local script="$1"
    
    log "Verifying script integrity..."
    
    # Check if file exists and is not empty
    if [[ ! -f "$script" ]] || [[ ! -s "$script" ]]; then
        error "Downloaded file is missing or empty"
        return 1
    fi
    
    # Check if it's a valid shell script (check shebang)
    local first_line=$(head -n1 "$script")

    if [[ ! "$first_line" =~ ^#! ]]; then
        error "Downloaded file is missing shebang"
        return 1
    fi
    
    # Check for suspicious content
    if grep -qE '(eval.*base64|curl.*\|.*sh|wget.*\|.*sh)' "$script"; then
        warn "Script contains potentially dangerous patterns"
        
        if [[ "$PIPE_MODE" == true ]]; then
            die "Verification failed: script contains suspicious patterns. Review manually."
        else
            warn "Please review: $script"
            echo -n "Continue anyway? [y/N] "
            read -r response
            [[ ! "$response" =~ ^[Yy]$ ]] && return 1
        fi
    fi
    
    # Basic syntax check
    if ! bash -n "$script" 2>/dev/null; then
        error "Script has syntax errors"
        return 1
    fi
    
    log "Script verification passed"
    return 0
}

# Check dependencies with detailed reporting
check_dependencies() {
    info "Checking dependencies..."
    
    local required_deps=("jq" "tar")
    local optional_deps=("sha256sum" "shasum")
    local missing_required=()
    local checksum_tool=""
    
    # Check required dependencies
    for cmd in "${required_deps[@]}"; do
        if has_command "$cmd"; then
            success "$cmd found"
        else
            error "$cmd not found (required)"
            missing_required+=("$cmd")
        fi
    done
    
    # Check for at least one checksum tool
    for cmd in "${optional_deps[@]}"; do
        if has_command "$cmd"; then
            success "$cmd found"
            checksum_tool="$cmd"
            break
        fi
    done
    
    if [[ -z "$checksum_tool" ]]; then
        error "No checksum tool found (need sha256sum or shasum)"
        missing_required+=("sha256sum")
    fi
    
    # Report missing dependencies
    if [[ ${#missing_required[@]} -gt 0 ]]; then
        echo
        error "Missing required dependencies: ${missing_required[*]}"
        echo
        
        # Detect OS and suggest installation command
        local install_cmd
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            case "${ID:-unknown}" in
                arch|manjaro)
                    install_cmd="sudo pacman -S ${missing_required[*]}"
                    ;;
                ubuntu|debian|pop|linuxmint)
                    install_cmd="sudo apt update && sudo apt install ${missing_required[*]}"
                    ;;
                fedora|rhel|centos)
                    install_cmd="sudo dnf install ${missing_required[*]}"
                    ;;
                opensuse*)
                    install_cmd="sudo zypper install ${missing_required[*]}"
                    ;;
                alpine)
                    install_cmd="sudo apk add ${missing_required[*]}"
                    ;;
                *)
                    install_cmd="Use your package manager to install: ${missing_required[*]}"
                    ;;
            esac
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            install_cmd="brew install ${missing_required[*]}"
        else
            install_cmd="Use your package manager to install: ${missing_required[*]}"
        fi
        
        echo "Install them with:"
        echo "  $install_cmd"
        echo
        
        die "Cannot continue without required dependencies"
    fi
    
    echo
    log "All dependencies satisfied"
}

# Detect shell with improved detection
detect_shell() {
    local shell_name shell_path
    
    # Try $SHELL first
    if [[ -n "${SHELL:-}" ]]; then
        shell_path="$SHELL"
    # Fallback to parent process
    elif [[ -n "${BASH:-}" ]]; then
        shell_path="$BASH"
    else
        shell_path=$(ps -p $$ -o comm= 2>/dev/null || echo "sh")
    fi
    
    shell_name=$(basename "$shell_path")
    
    case "$shell_name" in
        bash) echo "bash" ;;
        zsh) echo "zsh" ;;
        fish) echo "fish" ;;
        *) echo "unknown" ;;
    esac
}

# Get shell config file with validation
get_shell_config() {
    local shell_type="$1"
    local config_file=""
    
    case "$shell_type" in
        bash)
            # Prefer .bashrc for interactive shells
            if [[ -f "$HOME/.bashrc" ]]; then
                config_file="$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                config_file="$HOME/.bash_profile"
            elif [[ -f "$HOME/.profile" ]]; then
                config_file="$HOME/.profile"
            else
                config_file="$HOME/.bashrc"  # Create new
            fi
            ;;
        zsh)
            config_file="${ZDOTDIR:-$HOME}/.zshrc"
            ;;
        fish)
            config_file="$HOME/.config/fish/config.fish"
            ;;
        *)
            return 1
            ;;
    esac
    
    echo "$config_file"
}

# Backup existing file
backup_file() {
    local file="$1"
    
    if [[ -f "$file" ]]; then
        local backup="${file}.backup-$(date +%Y%m%d-%H%M%S)"
        cp "$file" "$backup"
        log "Created backup: $backup"
        echo "$backup"
    fi
}

# Setup PATH with idempotent configuration
setup_path() {
    local shell_type
    shell_type=$(detect_shell)
    
    if [[ "$shell_type" == "unknown" ]]; then
        warn "Unknown shell ($SHELL), skipping automatic PATH setup"
        return 1
    fi
    
    local config_file
    config_file=$(get_shell_config "$shell_type")
    
    if [[ -z "$config_file" ]]; then
        warn "Could not determine shell config file"
        return 1
    fi
    
    # Check if already configured
    if [[ -f "$config_file" ]] && grep -q "# zix - Zig Version Manager" "$config_file" 2>/dev/null; then
        success "PATH already configured in $config_file"
        return 0
    fi
    
    info "Adding $BIN_DIR to PATH in $config_file..."
    
    # Create backup
    if [[ -f "$config_file" ]]; then
        backup_file "$config_file" >/dev/null
    fi
    
    # Create directory if needed
    mkdir -p "$(dirname "$config_file")"
    touch "$config_file"
    
    # Add PATH configuration with idempotency guard
    {
        echo ""
        echo "# zix - Zig Version Manager"
        echo "# Added by zix installer on $(date +'%Y-%m-%d %H:%M:%S')"
        
        if [[ "$shell_type" == "fish" ]]; then
            echo "if not contains $BIN_DIR \$PATH"
            echo "    set -gx PATH $BIN_DIR \$PATH"
            echo "end"
        else
            echo "if [[ \":\$PATH:\" != *\":$BIN_DIR:\"* ]]; then"
            echo "    export PATH=\"$BIN_DIR:\$PATH\""
            echo "fi"
        fi
    } >> "$config_file"
    
    success "Added to PATH in $config_file"
    log "PATH configuration added to $config_file"
    return 0
}

# Verify installation
verify_installation() {
    info "Verifying installation..."
    
    # Check if zix script exists
    if [[ ! -f "$ZIX_SCRIPT" ]]; then
        error "zix script not found at $ZIX_SCRIPT"
        return 1
    fi
    
    # Check if executable
    if [[ ! -x "$ZIX_SCRIPT" ]]; then
        error "zix script is not executable"
        return 1
    fi
    
    # Check symlink
    if [[ ! -L "$ZIX_SYMLINK" ]]; then
        error "zix symlink not found at $ZIX_SYMLINK"
        return 1
    fi
    
    # Verify symlink target
    if [[ "$(readlink "$ZIX_SYMLINK")" != "$ZIX_SCRIPT" ]]; then
        error "zix symlink points to wrong target"
        return 1
    fi
    
    success "Installation verified"
    log "Installation verification passed"
    return 0
}

# Show post-installation instructions
show_instructions() {
    local shell_type
    shell_type=$(detect_shell)
    local config_file
    config_file=$(get_shell_config "$shell_type")
    
    echo
    success "Installation complete!"
    echo
    
    info "Next steps:"
    echo
    echo "  1. Reload your shell configuration:"
    if [[ -n "$config_file" ]] && [[ "$shell_type" != "unknown" ]]; then
        case "$shell_type" in
            fish)
                echo "     source $config_file"
                ;;
            *)
                echo "     source $config_file"
                echo "     # or simply start a new terminal session"
                ;;
        esac
    else
        echo "     export PATH=\"$BIN_DIR:\$PATH\""
    fi
    echo
    
    echo "  2. Verify installation:"
    echo "     zix doctor"
    echo
    
    echo "  3. Install Zig:"
    echo "     zix install 0.13.0        # Install specific version"
    echo "     zix nightly               # Install latest nightly"
    echo "     zix list-remote           # See all available versions"
    echo
    
    echo "  4. Use a version:"
    echo "     zix use 0.13.0"
    echo "     zix auto                  # Use version from .zig-version"
    echo
    
    info "Useful commands:"
    echo
    echo "  zix list                      # List installed versions"
    echo "  zix current                   # Show current version"
    echo "  zix remove <version>          # Remove a version"
    echo "  zix --help                    # Show all commands"
    echo
    
    info "Documentation:"
    echo "  https://codeberg.org/erffy/zix"
    echo
}

# Interactive completion installation
install_completions() {
    if [[ "$PIPE_MODE" == true ]]; then
        # Skip interactive prompt in pipe mode
        info "Shell completions can be installed later with: zix completion-install"
        return
    fi
    
    echo
    echo -n "Install shell completions? [Y/n] "
    read -r response
    response=${response:-Y}  # Default to Yes
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo
        info "Installing shell completions..."
        if "$ZIX_SYMLINK" completion-install >> "$LOG_FILE" 2>&1; then
            success "Shell completions installed"
            warn "Restart your shell to activate completions"
        else
            warn "Failed to install shell completions"
            warn "You can install them later with: zix completion-install"
        fi
    else
        info "Skipped shell completions (install later with: zix completion-install)"
    fi
}

# Main installation flow
main() {
    print_banner
    
    log "=== Installation started ==="
    log "Installer version: $INSTALLER_VERSION"
    log "Pipe mode: $PIPE_MODE"
    log "ZIX_URL: $ZIX_URL"
    log "ZIG_HOME: $ZIG_HOME"
    log "BIN_DIR: $BIN_DIR"
    log "Shell: $SHELL"
    log "User: $USER"
    log "Home: $HOME"
    
    # Validate environment
    validate_environment
    
    info "Installing zix (Zig Version Manager)..."
    echo
    
    # Check dependencies first
    check_dependencies
    
    # Detect downloader
    local downloader
    if ! downloader=$(detect_downloader); then
        die "No download tool found. Please install curl, wget, or aria2."
    fi
    info "Using $downloader for downloads"
    log "Downloader: $downloader"
    echo
    
    # Create directories with proper permissions
    info "Creating directories..."
    if ! mkdir -p "$ZIG_HOME" "$BIN_DIR" 2>>"$LOG_FILE"; then
        die "Failed to create directories"
    fi
    success "Created $ZIG_HOME"
    success "Created $BIN_DIR"
    echo
    
    # Download zix script
    info "Downloading zix from $ZIX_URL..."
    local tmp_script="$ZIX_SCRIPT.tmp"
    
    if ! download_file "$ZIX_URL" "$tmp_script" "$downloader"; then
        rm -f "$tmp_script"
        die "Failed to download zix script"
    fi
    
    # Verify downloaded script
    if ! verify_script "$tmp_script"; then
        rm -f "$tmp_script"
        die "Script verification failed"
    fi
    
    # Backup existing installation
    if [[ -f "$ZIX_SCRIPT" ]]; then
        backup_file "$ZIX_SCRIPT" >/dev/null
        info "Backed up existing installation"
    fi
    
    # Move to final location
    mv "$tmp_script" "$ZIX_SCRIPT"
    success "Downloaded and verified zix"
    echo
    
    # Setup zix
    info "Setting up zix..."
    chmod +x "$ZIX_SCRIPT" || die "Failed to make zix executable"
    success "Made zix executable"
    
    # Create or update symlink
    if [[ -L "$ZIX_SYMLINK" ]] || [[ -f "$ZIX_SYMLINK" ]]; then
        rm -f "$ZIX_SYMLINK"
    fi
    if ! ln -sf "$ZIX_SCRIPT" "$ZIX_SYMLINK" 2>>"$LOG_FILE"; then
        die "Failed to create symlink"
    fi
    success "Created symlink: $ZIX_SYMLINK -> $ZIX_SCRIPT"
    echo
    
    # Verify installation
    if ! verify_installation; then
        die "Installation verification failed"
    fi
    echo
    
    # Configure shell environment
    info "Configuring shell environment..."
    if setup_path; then
        echo
    else
        echo
        warn "Could not automatically configure PATH"
        warn "Add this to your shell configuration file:"
        echo
        echo "  export PATH=\"$BIN_DIR:\$PATH\""
        echo
    fi
    
    # Show completion instructions
    show_instructions
    
    # Optional: Install completions
    install_completions
    
    echo
    success "Happy Zigging! 🦎"
    echo
    
    log "=== Installation completed successfully ==="
}

# Run installation
main "$@"