#!/bin/bash
################################################################################
# EzMAP2 — Automated Installer
#
# Installs all dependencies needed to run EzMAP2:
#   1. Miniconda (if not already installed)
#   2. QIIME2 2024.10 conda environment
#   3. R + Shiny + Bioconductor packages for downstream analysis
#
# This script can be run from ANY directory. It does not require a specific
# installation location (e.g., Desktop). All conda environments are installed
# in the standard conda location (~/.conda or ~/miniconda3).
#
# Usage:
#   bash install.sh              # Interactive mode (prompts for confirmation)
#   bash install.sh --yes        # Non-interactive mode (auto-accept all prompts)
#   bash install.sh --skip-qiime # Skip QIIME2 installation (downstream only)
#   bash install.sh --skip-r     # Skip R installation
#
# The script is safe to re-run — it skips components that are already installed.
################################################################################

set -e

# ---- Color codes ----
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---- Configuration ----
QIIME2_ENV_NAME="EzMAP2-qiime2"
QIIME2_VERSION="2024.10"
QIIME2_YML_URL="https://data.qiime2.org/distro/amplicon/qiime2-amplicon-${QIIME2_VERSION}-py310-linux-conda.yml"
MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"

# ---- Parse arguments ----
AUTO_YES=false
SKIP_QIIME=false
SKIP_R=false

for arg in "$@"; do
    case "$arg" in
        --yes|-y)       AUTO_YES=true ;;
        --skip-qiime)   SKIP_QIIME=true ;;
        --skip-r)       SKIP_R=true ;;
        --help|-h)
            echo "Usage: bash install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --yes, -y       Auto-accept all prompts (non-interactive)"
            echo "  --skip-qiime    Skip QIIME2 installation (downstream analysis only)"
            echo "  --skip-r        Skip R and Shiny package installation"
            echo "  --help, -h      Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg (use --help for usage)"
            exit 1
            ;;
    esac
done

# Auto-detect non-interactive mode (e.g., called from Java GUI)
if [ ! -t 0 ]; then
    AUTO_YES=true
fi

# ---- Helper functions ----
info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $1"; }

pause() {
    if [ "$AUTO_YES" = true ]; then
        echo "  (auto-continuing)"
    else
        read -rp "  $1"
    fi
}

ask_yes() {
    if [ "$AUTO_YES" = true ]; then
        info "$1 → auto: yes"
        return 0
    else
        read -rp "  $1 (y/n) " -n 1 REPLY
        echo
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}

# ---- Error handler ----
handle_error() {
    local exit_code="$?"
    local command_failed="$BASH_COMMAND"
    echo ""
    fail "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fail "An error occurred during installation."
    fail "Command: $command_failed"
    fail "Exit code: $exit_code"
    echo ""
    if [[ "$command_failed" == *"wget"* ]] || [[ "$command_failed" == *"curl"* ]]; then
        warn "This looks like a network error."
        warn "Suggestions:"
        warn "  1. Check your internet connection"
        warn "  2. If using WSL, try: wsl --shutdown (from PowerShell), then restart"
        warn "  3. Try again in a few minutes (server may be temporarily unavailable)"
    elif [[ "$command_failed" == *"conda env create"* ]]; then
        warn "Conda environment creation failed."
        warn "Suggestions:"
        warn "  1. Check if environment already exists: conda env list"
        warn "  2. Remove and retry: conda env remove -n $QIIME2_ENV_NAME"
        warn "  3. Check disk space: df -h ~"
    elif [[ "$command_failed" == *"miniconda"* ]]; then
        warn "Miniconda installation failed."
        warn "Suggestions:"
        warn "  1. Remove old installation: rm -rf ~/miniconda3"
        warn "  2. Re-run this script"
    fi
    fail "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    pause "Press Enter to exit..."
    exit "$exit_code"
}
trap 'handle_error' ERR

# ---- Detect script location ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Banner ----
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║          EzMAP2 — Automated Installer                   ║${NC}"
echo -e "${BOLD}${GREEN}║          Easy Microbiome Analysis Pipeline v2            ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
info "Installation directory: $SCRIPT_DIR"
info "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# ============================================================================
# Step 1: Internet Connectivity Check
# ============================================================================
echo -e "${BOLD}━━━ Step 1/4: Internet Connectivity ━━━${NC}"
info "Checking internet connection..."

if command -v wget &>/dev/null; then
    if ! wget -q --spider --timeout=10 http://google.com 2>/dev/null; then
        fail "Cannot reach the internet. Please check your connection."
        if grep -qi microsoft /proc/version 2>/dev/null; then
            warn "WSL detected — try running 'wsl --shutdown' from PowerShell and restarting."
        fi
        exit 1
    fi
elif command -v curl &>/dev/null; then
    if ! curl -s --head --connect-timeout 10 http://google.com >/dev/null 2>&1; then
        fail "Cannot reach the internet. Please check your connection."
        exit 1
    fi
else
    warn "Neither wget nor curl found. Skipping connectivity check."
fi

ok "Internet connection verified."
echo ""

# ============================================================================
# Step 2: Miniconda Installation
# ============================================================================
echo -e "${BOLD}━━━ Step 2/4: Miniconda ━━━${NC}"

# Find existing conda installation
CONDA_FOUND=false
CONDA_SH=""

if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
    CONDA_SH="$HOME/miniconda3/etc/profile.d/conda.sh"
    CONDA_FOUND=true
elif [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
    CONDA_SH="$HOME/anaconda3/etc/profile.d/conda.sh"
    CONDA_FOUND=true
elif [ -f "$HOME/miniforge3/etc/profile.d/conda.sh" ]; then
    CONDA_SH="$HOME/miniforge3/etc/profile.d/conda.sh"
    CONDA_FOUND=true
elif command -v conda &>/dev/null; then
    CONDA_FOUND=true
    CONDA_SH="$(conda info --base 2>/dev/null)/etc/profile.d/conda.sh"
fi

if [ "$CONDA_FOUND" = true ]; then
    ok "Conda is already installed."
    info "Location: $(dirname "$(dirname "$CONDA_SH")")"
else
    info "Conda is not installed. Installing Miniconda..."

    MINICONDA_INSTALLER="/tmp/miniconda_installer.sh"

    if command -v wget &>/dev/null; then
        wget -q --show-progress "$MINICONDA_URL" -O "$MINICONDA_INSTALLER"
    else
        curl -L --progress-bar "$MINICONDA_URL" -o "$MINICONDA_INSTALLER"
    fi

    bash "$MINICONDA_INSTALLER" -b -p "$HOME/miniconda3"
    rm -f "$MINICONDA_INSTALLER"

    CONDA_SH="$HOME/miniconda3/etc/profile.d/conda.sh"
    ok "Miniconda installed to ~/miniconda3"
fi

# Activate conda in current shell
# shellcheck disable=SC1090
source "$CONDA_SH"

# Accept Anaconda channel Terms of Service (required since conda 24.9+)
info "Accepting conda channel Terms of Service..."
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main 2>/dev/null || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r    2>/dev/null || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/msys2 2>/dev/null || true

# Update conda
info "Updating conda..."
conda update conda -y -q 2>/dev/null || true
ok "Conda is ready."
echo ""

# ============================================================================
# Step 3: QIIME2 Environment
# ============================================================================
echo -e "${BOLD}━━━ Step 3/4: QIIME2 Environment ━━━${NC}"

if [ "$SKIP_QIIME" = true ]; then
    warn "QIIME2 installation skipped (--skip-qiime flag)."
    warn "You can still use EzMAP2 for downstream analysis only."
elif conda env list 2>/dev/null | grep -q "^${QIIME2_ENV_NAME} "; then
    ok "QIIME2 environment '${QIIME2_ENV_NAME}' already exists."

    # Verify QIIME2 is functional
    info "Verifying QIIME2 installation..."
    if conda run -n "$QIIME2_ENV_NAME" qiime --version &>/dev/null; then
        QVER=$(conda run -n "$QIIME2_ENV_NAME" qiime --version 2>&1 | head -1)
        ok "QIIME2 verified: $QVER"
    else
        warn "QIIME2 environment exists but 'qiime' command failed."
        warn "You may need to recreate: conda env remove -n $QIIME2_ENV_NAME"
    fi
else
    if ask_yes "Install QIIME2 ${QIIME2_VERSION}? (Required for upstream analysis, ~5 GB)"; then
        info "Downloading QIIME2 environment specification..."
        YML_FILE="/tmp/qiime2-${QIIME2_VERSION}.yml"

        if command -v wget &>/dev/null; then
            wget -q --show-progress "$QIIME2_YML_URL" -O "$YML_FILE"
        else
            curl -L --progress-bar "$QIIME2_YML_URL" -o "$YML_FILE"
        fi

        info "Creating QIIME2 environment (this takes 15-30 minutes)..."
        conda env create -n "$QIIME2_ENV_NAME" --file "$YML_FILE"
        rm -f "$YML_FILE"

        ok "QIIME2 ${QIIME2_VERSION} installed in environment '${QIIME2_ENV_NAME}'."
    else
        warn "QIIME2 installation skipped. You can still use downstream analysis."
    fi
fi
echo ""

# ============================================================================
# Step 4: R + Shiny Packages
# ============================================================================
echo -e "${BOLD}━━━ Step 4/4: R + Shiny Packages ━━━${NC}"

if [ "$SKIP_R" = true ]; then
    warn "R installation skipped (--skip-r flag)."
elif command -v Rscript &>/dev/null; then
    R_VER=$(Rscript --version 2>&1 | head -1)
    ok "R is already installed: $R_VER"

    # Check for critical packages
    info "Checking required R packages..."
    HAS_SHINY=$(Rscript -e 'cat(requireNamespace("shiny", quietly=TRUE))' 2>/dev/null || echo "FALSE")
    HAS_PHYLOSEQ=$(Rscript -e 'cat(requireNamespace("phyloseq", quietly=TRUE))' 2>/dev/null || echo "FALSE")

    if [ "$HAS_SHINY" = "TRUE" ] && [ "$HAS_PHYLOSEQ" = "TRUE" ]; then
        ok "Core R packages (shiny, phyloseq) are installed."
        info "Running full package check..."

        # Use the bundled R package installer if available
        R_INSTALLER="$SCRIPT_DIR/scripts/install_r_packages.R"
        if [ -f "$R_INSTALLER" ]; then
            Rscript "$R_INSTALLER" 2>/dev/null && ok "All R packages verified." \
                || warn "Some R packages may need manual installation."
        else
            ok "Skipping detailed check (install_r_packages.R not found)."
        fi
    else
        info "Installing missing R packages..."
        R_INSTALLER="$SCRIPT_DIR/scripts/install_r_packages.R"
        if [ -f "$R_INSTALLER" ]; then
            Rscript "$R_INSTALLER" && ok "R packages installed successfully." \
                || warn "Some packages failed. Run: Rscript scripts/install_r_packages.R"
        else
            # Fallback: install core packages inline
            Rscript -e "
                if (!requireNamespace('BiocManager', quietly=TRUE))
                    install.packages('BiocManager', repos='https://cloud.r-project.org', quiet=TRUE)
                BiocManager::install(c('phyloseq', 'DESeq2', 'biomformat'), ask=FALSE, update=FALSE, quiet=TRUE)
                install.packages(c(
                    'shiny', 'bslib', 'shinyjs', 'shinyWidgets', 'shinycssloaders',
                    'DT', 'plotly', 'ggplot2', 'ggrepel', 'vegan', 'ape',
                    'dplyr', 'tidyr', 'reshape2', 'pheatmap', 'RColorBrewer',
                    'viridis', 'scales', 'randomForest', 'igraph', 'sortable'
                ), repos='https://cloud.r-project.org', quiet=TRUE)
            " && ok "R packages installed." \
              || warn "Some packages failed. Check output above."
        fi
    fi
else
    info "R is not installed."

    if ask_yes "Install R + Shiny packages for downstream analysis?"; then
        # Detect if we should install via conda or system package manager
        if [ "$CONDA_FOUND" = true ] && conda env list 2>/dev/null | grep -q "^${QIIME2_ENV_NAME} "; then
            info "Installing R into the $QIIME2_ENV_NAME conda environment..."
            conda install -n "$QIIME2_ENV_NAME" -c conda-forge \
                r-base r-shiny r-bslib r-shinyjs r-dt r-plotly r-ggplot2 r-ggrepel \
                r-vegan r-ape r-dplyr r-tidyr r-reshape2 r-pheatmap r-rcolorbrewer \
                r-viridis r-scales r-randomforest r-igraph \
                bioconductor-phyloseq bioconductor-deseq2 bioconductor-biomformat \
                -y -q
            ok "R + packages installed in conda environment '${QIIME2_ENV_NAME}'."
        elif command -v apt &>/dev/null; then
            info "Installing R via apt..."
            sudo apt update -qq && sudo apt install -y r-base r-base-dev
            info "Installing R packages..."
            R_INSTALLER="$SCRIPT_DIR/scripts/install_r_packages.R"
            if [ -f "$R_INSTALLER" ]; then
                Rscript "$R_INSTALLER"
            fi
            ok "R installed via apt."
        else
            warn "Cannot auto-install R on this system."
            warn "Please install R manually:"
            warn "  Ubuntu:  sudo apt install r-base"
            warn "  macOS:   brew install r"
            warn "  Conda:   conda install -c conda-forge r-base r-shiny"
        fi
    else
        warn "R installation skipped. Downstream analysis will not be available."
    fi
fi
echo ""

# ============================================================================
# Summary
# ============================================================================
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║          Installation Complete!                          ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check what's available
echo -e "${BOLD}Component Status:${NC}"

# Java
if command -v java &>/dev/null; then
    JAVA_VER=$(java -version 2>&1 | head -1)
    ok "Java:    $JAVA_VER"
else
    warn "Java:    NOT FOUND — install Java 11+ to run EzMAP2"
fi

# Maven
if command -v mvn &>/dev/null; then
    ok "Maven:   $(mvn -version 2>&1 | head -1)"
else
    warn "Maven:   NOT FOUND — needed to build from source (bash build.sh)"
fi

# Conda
if command -v conda &>/dev/null; then
    ok "Conda:   $(conda --version 2>&1)"
else
    warn "Conda:   NOT FOUND"
fi

# QIIME2
if conda env list 2>/dev/null | grep -q "^${QIIME2_ENV_NAME} "; then
    ok "QIIME2:  Environment '${QIIME2_ENV_NAME}' ready"
else
    warn "QIIME2:  NOT INSTALLED (upstream analysis unavailable)"
fi

# R
if command -v Rscript &>/dev/null; then
    ok "R:       $(Rscript --version 2>&1 | head -1)"
else
    warn "R:       NOT FOUND (downstream analysis unavailable)"
fi

# JAR
if [ -f "$SCRIPT_DIR/EzMAP2.jar" ]; then
    ok "JAR:     $SCRIPT_DIR/EzMAP2.jar"
else
    warn "JAR:     NOT BUILT — run 'bash build.sh' to compile"
fi

echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Build the JAR (if not done):  bash build.sh"
echo "  2. Launch EzMAP2:                bash ezmap2.sh"
echo ""
pause "Press Enter to close..."
