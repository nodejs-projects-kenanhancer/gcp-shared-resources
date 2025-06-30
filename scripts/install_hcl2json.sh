#!/bin/bash
set -euo pipefail

print_usage() {
    echo "Usage: $(basename "$0") [VERSION]"
    echo ""
    echo "Installs tmccombs/hcl2json for your OS/ARCH from GitHub releases."
    echo "Defaults to v0.6.5 if VERSION is not specified."
    echo ""
    echo "Example:"
    echo " $(basename "$0") v0.6.5"
    exit 1
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    print_usage
fi

VERSION="${1:-"0.6.5"}"
# Strip 'v' prefix if present for URL construction
VERSION_NUM="${VERSION#v}"

# Detect OS
OS="$(uname -s | tr '[:upper:]' '[:lower:]')" # e.g. "linux", "darwin"

# Detect architecture
ARCH="$(uname -m)" # e.g. "x86_64", "arm64", "aarch64"

# Normalize ARCH to match release naming
# hcl2json uses "amd64" and "arm64" for 64-bit builds
case "$ARCH" in
x86_64)
    ARCH="amd64"
    ;;
aarch64 | arm64)
    ARCH="arm64"
    ;;
*)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

# Construct the filename; for example: hcl2json_darwin_arm64
FILENAME="hcl2json_${OS}_${ARCH}"
DOWNLOAD_URL="https://github.com/tmccombs/hcl2json/releases/download/v${VERSION_NUM}/${FILENAME}"
INSTALL_DIR="/usr/local/bin"

echo "Detected OS=$OS, ARCH=$ARCH"
echo "Installing hcl2json $VERSION from $DOWNLOAD_URL to $INSTALL_DIR"

# Create temporary directory
TMP_DIR="$(mktemp -d)"

# Download
curl -sL "$DOWNLOAD_URL" -o "${TMP_DIR}/hcl2json"

# Make executable and move to install directory
chmod +x "${TMP_DIR}/hcl2json"
sudo mv "${TMP_DIR}/hcl2json" "${INSTALL_DIR}/hcl2json"

# Cleanup
rm -rf "$TMP_DIR"

echo "hcl2json $VERSION installed successfully to ${INSTALL_DIR}."
echo "hcl2json --version:"
"${INSTALL_DIR}/hcl2json" --version
