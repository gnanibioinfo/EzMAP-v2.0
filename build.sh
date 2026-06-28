#!/bin/bash
# =============================================================================
# EzMAP2 — Build from source (Linux / macOS)
# Requires: Java 11+, Maven 3.6+
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "========================================"
echo "  EzMAP2 — Building from source"
echo "========================================"
echo ""

# Check Maven
if ! command -v mvn &>/dev/null; then
    echo "ERROR: Maven is not installed."
    echo ""
    echo "Install with:"
    echo "  Ubuntu:  sudo apt install maven"
    echo "  macOS:   brew install maven"
    exit 1
fi

# Build
cd "$SCRIPT_DIR/src-build"
echo "Building EzMAP2..."
mvn clean package -q

if [ $? -ne 0 ]; then
    echo ""
    echo "BUILD FAILED. Check errors above."
    exit 1
fi

# Copy JAR to distribution root
cp -f target/EzMAP2.jar "$SCRIPT_DIR/EzMAP2.jar"

echo ""
echo "========================================"
echo "  BUILD SUCCESSFUL"
echo "  JAR: $SCRIPT_DIR/EzMAP2.jar"
echo "========================================"
echo ""
