# ZIX - Zig Version Manager

A fast, lightweight, and powerful Zig version manager written in pure Bash.<br>
Manage multiple Zig versions effortlessly with intelligent caching, parallel downloads, and automatic version detection.

## Features

- 🚀 **Lightning Fast** - Parallel downloads with aria2c support (up to 16x faster)
- 🎯 **Smart Version Detection** - Auto-detects `.zigversion` files in project directories
- 📦 **Multiple Versions** - Install and switch between any Zig version instantly
- 🔄 **Automatic Updates** - Built-in self-update mechanism
- 💾 **Intelligent Caching** - Reduces redundant downloads with TTL-based caching
- 🌐 **Mirror Selection** - Auto-selects fastest mirror for optimal download speeds
- 🛠️ **Zero Dependencies*** - Works with curl, wget, or aria2c (choose your favorite)
- 🐚 **Shell Completions** - Tab completion for bash, zsh, and fish
- 🔍 **Directory Traversal** - Searches for version files up the directory tree

<sub>* Core dependencies: `jq`, `tar`, `sha256sum` (typically pre-installed)</sub>

## Installation

```bash
curl -fsSL https://codeberg.org/erffy/zix/raw/branch/master/install.sh | bash
```

### Custom Installation

```bash
# Custom directories
ZIG_HOME=/opt/zig ZIX_BIN_DIR=/usr/local/bin ./install.sh

# Force specific downloader
ZIX_DOWNLOADER=aria2c ./install.sh
```

### Manual Installation

```bash
# Create directories
mkdir -p ~/.zig ~/.local/bin

# Download zix
curl -fsSL https://codeberg.org/erffy/zix/raw/branch/master/zix -o ~/.zig/zix.sh
chmod +x ~/.zig/zix.sh

# Create symlink
ln -sf ~/.zig/zix.sh ~/.local/bin/zix

# Add to PATH (add to your shell config)
export PATH="$HOME/.local/bin:$PATH"
```

## System Requirements

### Required Dependencies

- `bash` 4.0+
- `jq` - JSON parsing
- `tar` - Archive extraction
- `sha256sum` or `shasum` - Checksum verification
- One of: `curl`, `wget`, or `aria2c` - Downloads

### Recommended

- `aria2c` - For parallel downloads (10-16x faster)

### Installation Commands

```bash
# Arch Linux
sudo pacman -S jq tar coreutils aria2

# Debian/Ubuntu
sudo apt install jq tar coreutils aria2

# Fedora
sudo dnf install jq tar coreutils aria2

# macOS
brew install jq aria2
```

## Supported Platforms

| Platform | Architecture                           |
|:---------|:---------------------------------------|
| Linux    | x86_64, aarch64, arm, riscv64, ppc64le |
| macOS    | x86_64, aarch64                        |
| FreeBSD  | x86_64, aarch64, arm                   |
| NetBSD   | x86_64, aarch64                        |

## Quick Start

```bash
# Verify installation
zix doctor

# Install latest stable version
zix install 0.13.0

# Or install latest nightly
zix nightly

# Switch to a version
zix use 0.13.0

# Verify it's working
zig version
```

## Usage

### Basic Commands

```bash
# Install a specific version
zix install 0.13.0
zix install 0.11.0
zix install master      # Development version

# List installed versions
zix list

# List all available versions
zix list-remote

# Use a specific version
zix use 0.13.0

# Show current version
zix current

# Remove a version
zix remove 0.11.0
```

### Project Version Management

Create a `.zigversion` file in your project:

```bash
echo "0.13.0" > .zigversion
```

Then use auto-detection:

```bash
zix auto
```

ZIX will search up the directory tree to find the version file, automatically install if needed, and activate it.

**Supported version files:**
- `.zig-version`
- `.zigversion`
- `.zv`

### Nightly Builds

```bash
# Install and use latest nightly
zix nightly

# Nightly versions are named like: 0.14.0-dev.1234+hash
```

### Advanced Usage

```bash
# Check installation and configuration
zix doctor

# Show environment setup
zix env

# Clean download cache
zix clean

# Install shell completions
zix completion-install

# Update zix itself
zix update-self
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ZIG_HOME` | Installation directory | `~/.zig` |
| `ZIX_BIN_DIR` | Binary directory | `~/.local/bin` |
| `ZIX_DOWNLOADER` | Force downloader: `aria2c`, `curl`, or `wget` | Auto-detect |

### Examples

```bash
# Use custom installation directory
export ZIG_HOME="/opt/zig"
zix install 0.13.0

# Force curl for downloads (useful in restricted environments)
ZIX_DOWNLOADER=curl zix install master

# Use custom binary location
export ZIX_BIN_DIR="/usr/local/bin"
```

## Shell Integration

### Automatic PATH Setup

The installer automatically configures your shell. To manually add:

**Bash/Zsh** (`~/.bashrc` or `~/.zshrc`):
```bash
export PATH="$HOME/.local/bin:$PATH"
```

**Fish** (`~/.config/fish/config.fish`):
```fish
fish_add_path "$HOME/.local/bin"
```

### Shell Completions

```bash
# Install completions for your shell
zix completion-install

# Restart your shell or reload config
source ~/.bashrc  # or ~/.zshrc or ~/.config/fish/config.fish
```

## Performance

ZIX is designed for speed:

- **Parallel Downloads**: aria2c uses up to 16 connections
- **Smart Caching**: 6-hour TTL reduces redundant API calls
- **Fast Mirror Selection**: Automatically picks nearest mirror
- **Efficient Extraction**: Optimized tar operations

*Results vary based on connection and mirror availability*

## 🛠️ Troubleshooting

### Installation Issues

```bash
# Check what's wrong
zix doctor

# Check installation log (during install)
cat /tmp/zix-install-*.log

# Verify dependencies
command -v jq tar sha256sum curl
```

### Common Issues

**Problem:** `zix: command not found`
```bash
# Ensure ~/.local/bin is in PATH
echo $PATH | grep -q "$HOME/.local/bin" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**Problem:** Download fails
```bash
# Try different downloader
ZIX_DOWNLOADER=wget zix install 0.13.0

# Or clear cache and retry
zix clean
zix install 0.13.0
```

**Problem:** Version not found
```bash
# List available versions
zix list-remote

# Install specific version
zix install 0.13.0
```

**Problem:** Permission denied
```bash
# Don't run as root - zix is per-user
# Ensure home directory is writable
ls -ld ~
```

## Updating

```bash
# Update zix itself
zix update-self

# Update to latest nightly
zix nightly
```

## Uninstallation

```bash
# Remove all installed Zig versions
rm -rf ~/.zig

# Remove zix
rm -f ~/.local/bin/zix

# Remove from shell config (manual)
# Edit ~/.bashrc, ~/.zshrc, or ~/.config/fish/config.fish
# Remove the zix PATH export line
```

## Version File Format

Simple text file with version number:

```
# .zigversion example
0.13.0
```

**Features:**
- Comments supported (lines starting with `#`)
- Whitespace is ignored
- First non-comment line is used

**Example:**
```
# Project Zig version
# Updated: 2024-01-06
0.13.0
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## 🙏 Acknowledgments

- Inspired by [nvm](https://github.com/nvm-sh/nvm), [rbenv](https://github.com/rbenv/rbenv), and other version managers
- Built for the [Zig](https://ziglang.org) community
- Powered by [aria2](https://aria2.github.io) for blazing fast downloads

---

<div align="center">

**Made with ❤️ by Me**

*Star ⭐ this repo if you find it useful!*

This project is licensed under the **GNU General Public License v3.0**. See [LICENSE](./LICENSE) for details.

</div>