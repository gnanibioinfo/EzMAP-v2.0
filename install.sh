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
echo -e "${BOLD}${GREEN}║          EzMAP2 — Automated Installer                    ║${NC}"
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

# ----------------------------------------------------------------------------
# IMPORTANT: the R step must NEVER abort the whole installer. QIIME2 (upstream
# analysis) is already installed in Step 3, and R is only needed for downstream
# analysis. Installing R packages can be slow and can hit transient/optional
# errors, so we disable the fatal `set -e` / ERR trap for this section: any
# problem here degrades to a warning instead of killing the installation.
# ----------------------------------------------------------------------------
set +e
trap - ERR

info "R powers the optional Downstream Analysis module (not upstream QIIME2)."
info "Installing R packages can take 10-30 minutes the first time."
info "You can safely interrupt this step (Ctrl-C) — upstream analysis already"
info "works, and EzMAP2 will finish installing any missing R packages the first"
info "time you open the Downstream Analysis page."
echo ""

# Detect R on the base PATH OR already inside the QIIME2 conda env (where we
# install it). R in the conda env is NOT on the base-shell PATH, so checking
# only `command -v Rscript` wrongly reported "R is not installed" on every
# re-run and triggered a redundant conda solve.
RSCRIPT_CMD=""
if command -v Rscript &>/dev/null; then
    RSCRIPT_CMD="Rscript"
elif conda run -n "$QIIME2_ENV_NAME" Rscript --version &>/dev/null; then
    RSCRIPT_CMD="conda run -n $QIIME2_ENV_NAME Rscript"
fi

if [ "$SKIP_R" = true ]; then
    warn "R installation skipped (--skip-r flag)."
elif [ -n "$RSCRIPT_CMD" ]; then
    # shellcheck disable=SC2086
    R_VER=$($RSCRIPT_CMD --version 2>&1 | head -1)
    ok "R is already installed: $R_VER"

    # Verify/complete the package set. This is fast on re-runs: the installer
    # self-skips via its lock file once everything is in place.
    R_INSTALLER="$SCRIPT_DIR/scripts/install_r_packages.R"
    if [ -f "$R_INSTALLER" ]; then
        info "Verifying R packages..."
        # shellcheck disable=SC2086
        $RSCRIPT_CMD "$R_INSTALLER" && ok "R packages ready." \
            || warn "Some R packages will be installed on first Downstream launch."
    else
        ok "Skipping detailed check (install_r_packages.R not found)."
    fi
else
    info "R is not installed."

    if ask_yes "Install R + Shiny packages for downstream analysis?"; then
        # Detect if we should install via conda or system package manager
        if [ "$CONDA_FOUND" = true ] && conda env list 2>/dev/null | grep -q "^${QIIME2_ENV_NAME} "; then
            info "Installing R + core packages into the $QIIME2_ENV_NAME conda environment..."
            info "(conda binary packages — no source compilation; the wait is the solver)."

            # NOTE: bioconductor-* packages live on the 'bioconda' channel — the
            # previous command omitted it, which caused a "package not found"
            # error. We also prefer the much faster libmamba solver and fall
            # back to the classic solver if this conda build doesn't support it.
            R_CONDA_PKGS="r-base r-shiny r-bslib r-shinyjs r-dt r-plotly r-ggplot2 r-ggrepel \
                r-vegan r-ape r-dplyr r-tidyr r-reshape2 r-pheatmap r-rcolorbrewer \
                r-viridis r-scales r-randomforest r-igraph r-car r-proc r-fsa \
                r-rstatix r-ggsignif r-gtools \
                bioconductor-phyloseq bioconductor-deseq2 bioconductor-biomformat"

            # shellcheck disable=SC2086
            if conda install -n "$QIIME2_ENV_NAME" --solver=libmamba \
                    -c conda-forge -c bioconda $R_CONDA_PKGS -y 2>/dev/null \
               || conda install -n "$QIIME2_ENV_NAME" \
                    -c conda-forge -c bioconda $R_CONDA_PKGS -y; then
                ok "R + core packages installed in environment '${QIIME2_ENV_NAME}'."
                # Pick up any remaining CRAN/GitHub-only packages via the
                # optimized installer (PPM binaries — fast). Non-fatal.
                R_INSTALLER="$SCRIPT_DIR/scripts/install_r_packages.R"
                if [ -f "$R_INSTALLER" ]; then
                    info "Installing remaining R packages (optional helpers)..."
                    conda run -n "$QIIME2_ENV_NAME" Rscript "$R_INSTALLER" \
                        || warn "Some optional R packages will be installed on first downstream launch."
                fi
            else
                warn "R install via conda did not complete (often a transient solver/network issue)."
                warn "Upstream (QIIME2) analysis still works. EzMAP2 will retry the R package"
                warn "install automatically the first time you open Downstream Analysis."
            fi
        elif command -v apt &>/dev/null; then
            info "Installing R via apt..."
            sudo apt update -qq && sudo apt install -y r-base r-base-dev \
                || warn "apt R install hit an issue — see messages above."
            info "Installing R packages..."
            R_INSTALLER="$SCRIPT_DIR/scripts/install_r_packages.R"
            if [ -f "$R_INSTALLER" ]; then
                Rscript "$R_INSTALLER" \
                    || warn "Some R packages will be installed on first downstream launch."
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

# Java — the GUI runs on the HOST (your Windows Java when using WSL). This only
# checks the current shell, so "not here" inside WSL is expected and harmless.
if command -v java &>/dev/null; then
    ok "Java:    $(java -version 2>&1 | head -1)"
elif grep -qi microsoft /proc/version 2>/dev/null; then
    info "Java:    not inside WSL — that's fine, EzMAP2 runs on your Windows Java"
else
    warn "Java:    NOT FOUND — install Java 11+ to run EzMAP2"
fi

# Maven (only needed to build from source). Print [OK] only if it actually runs.
if command -v mvn &>/dev/null && mvn -version 2>/dev/null | grep -qi "Apache Maven"; then
    ok "Maven:   $(mvn -version 2>/dev/null | grep -i 'Apache Maven' | head -1)"
elif command -v mvn &>/dev/null; then
    info "Maven:   found, but JAVA_HOME not set in this shell (only needed to build from source)"
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

# R — installed INTO the QIIME2 conda env, so check there (it isn't on the base
# shell PATH until the env is activated, which the downstream launcher does).
if conda run -n "$QIIME2_ENV_NAME" Rscript --version &>/dev/null; then
    ok "R:       $(conda run -n "$QIIME2_ENV_NAME" Rscript --version 2>&1 | head -1) (in env '${QIIME2_ENV_NAME}')"
elif command -v Rscript &>/dev/null; then
    ok "R:       $(Rscript --version 2>&1 | head -1)"
else
    info "R:       not detected yet — it will be installed on first Downstream launch"
fi

# JAR
if [ -f "$SCRIPT_DIR/EzMAP2.jar" ]; then
    ok "JAR:     $SCRIPT_DIR/EzMAP2.jar"
else
    warn "JAR:     NOT BUILT — run 'bash build.sh' to compile"
fi

echo ""
# "Next steps" only apply to a manual install on native Linux/macOS. When this
# runs under WSL it was launched by the Windows EzMAP2 GUI, which handles
# building and launching for you — so the bash build.sh / ezmap2.sh hints would
# only confuse Windows users.
if grep -qi microsoft /proc/version 2>/dev/null; then
    echo -e "${BOLD}Setup complete.${NC} Return to the EzMAP2 window to continue."
else
    echo -e "${BOLD}Next steps:${NC}"
    echo "  1. Build the JAR (if not done):  bash build.sh"
    echo "  2. Launch EzMAP2:                bash ezmap2.sh"
fi
echo ""
pause "Press Enter to close..."
