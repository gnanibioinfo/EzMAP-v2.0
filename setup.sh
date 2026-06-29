#!/bin/bash
################################################################################
# EzMAP2 — One-Step Setup
#
# Downloads, installs dependencies, builds, and launches EzMAP2.
# Run this script from any directory where you want EzMAP2 installed.
#
# Quick start:
#   curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/EzMAP2/main/setup.sh | bash
#
# Or:
#   wget -qO- https://raw.githubusercontent.com/YOUR_USERNAME/EzMAP2/main/setup.sh | bash
#
# Or manually:
#   bash setup.sh [--install-dir /path/to/install]
#
# Options:
#   --install-dir <path>   Where to clone/install EzMAP2 (default: current dir)
#   --skip-qiime           Skip QIIME2 installation (downstream only)
#   --skip-r               Skip R installation
#   --yes                  Auto-accept all prompts
################################################################################

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $1"; exit 1; }

# ---- Parse arguments ----
INSTALL_DIR="$(pwd)"
EXTRA_ARGS=""
REPO_URL="https://github.com/YOUR_USERNAME/EzMAP2.git"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-dir)  INSTALL_DIR="$2"; shift 2 ;;
        --skip-qiime)   EXTRA_ARGS="$EXTRA_ARGS --skip-qiime"; shift ;;
        --skip-r)       EXTRA_ARGS="$EXTRA_ARGS --skip-r"; shift ;;
        --yes|-y)       EXTRA_ARGS="$EXTRA_ARGS --yes"; shift ;;
        --help|-h)
            echo "Usage: bash setup.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --install-dir <path>  Installation directory (default: current directory)"
            echo "  --skip-qiime          Skip QIIME2 (downstream analysis only)"
            echo "  --skip-r              Skip R and Shiny packages"
            echo "  --yes, -y             Auto-accept all prompts"
            exit 0
            ;;
        *)  fail "Unknown option: $1 (use --help)" ;;
    esac
done

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║          EzMAP2 — One-Step Setup                        ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ---- Step 1: Check prerequisites ----
info "Checking prerequisites..."

if ! command -v git &>/dev/null; then
    fail "git is not installed. Install with: sudo apt install git"
fi

if ! command -v java &>/dev/null; then
    info "Java is not installed. Attempting to install..."
    if command -v apt &>/dev/null; then
        sudo apt update -qq && sudo apt install -y default-jdk maven
    elif command -v brew &>/dev/null; then
        brew install openjdk@17 maven
    else
        fail "Java 11+ is required. Install it manually and re-run this script."
    fi
fi

if ! command -v mvn &>/dev/null; then
    info "Maven is not installed. Attempting to install..."
    if command -v apt &>/dev/null; then
        sudo apt install -y maven
    elif command -v brew &>/dev/null; then
        brew install maven
    else
        fail "Maven 3.6+ is required. Install it manually and re-run this script."
    fi
fi

ok "Prerequisites met."

# ---- Step 2: Clone repository ----
EZMAP2_DIR="$INSTALL_DIR/EzMAP2"

if [ -d "$EZMAP2_DIR" ]; then
    info "EzMAP2 directory already exists at: $EZMAP2_DIR"
    info "Pulling latest changes..."
    cd "$EZMAP2_DIR" && git pull --rebase 2>/dev/null || true
else
    info "Cloning EzMAP2 to: $EZMAP2_DIR"
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    git clone "$REPO_URL"
fi

cd "$EZMAP2_DIR"
ok "Repository ready at: $EZMAP2_DIR"

# ---- Step 3: Install dependencies ----
info "Running installer..."
# shellcheck disable=SC2086
bash install.sh $EXTRA_ARGS

# ---- Step 4: Build JAR ----
info "Building EzMAP2 from source..."
bash build.sh
ok "Build complete."

# ---- Done ----
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║          Setup Complete!                                 ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}To launch EzMAP2:${NC}"
echo "    cd $EZMAP2_DIR"
echo "    bash ezmap2.sh"
echo ""
echo -e "  ${BOLD}To create a desktop shortcut (Ubuntu):${NC}"
echo "    bash install-desktop.sh"
echo ""
