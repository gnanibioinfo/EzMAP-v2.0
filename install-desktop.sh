#!/bin/bash
# =============================================================================
# EzMAP2 — Ubuntu Desktop Installer
# =============================================================================
# Builds the uber JAR (if needed), makes the launcher executable,
# and installs a .desktop shortcut so EzMAP2 appears in the app menu
# and can be double-clicked from the file manager.
#
# Usage:  ./install-desktop.sh
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()  { echo -e "${GREEN}✓${NC} $*"; }
die() { echo -e "${RED}✗${NC} $*" >&2; exit 1; }
log() { echo -e "${CYAN}→${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JAR="$SCRIPT_DIR/target/EzMAP2.jar"

# ---- Step 1: Check Java ----
log "Checking Java…"
if ! command -v java >/dev/null 2>&1; then
    die "Java not found. Install with: sudo apt install default-jdk"
fi
JAVA_VER=$(java -version 2>&1 | head -1 | sed 's/.*"\([0-9]*\).*/\1/')
ok "Java $JAVA_VER found."

# ---- Step 2: Build if needed ----
if [[ ! -f "$JAR" ]]; then
    log "EzMAP2.jar not found — building with Maven…"
    if ! command -v mvn >/dev/null 2>&1; then
        die "Maven not found. Install with: sudo apt install maven"
    fi
    ( cd "$SCRIPT_DIR" && mvn clean package -q -DskipTests )
    [[ -f "$JAR" ]] || die "Build failed. Check Maven output above."
    ok "Built: $JAR"
else
    ok "JAR already exists: $JAR"
fi

# ---- Step 3: Make launcher executable ----
chmod +x "$SCRIPT_DIR/ezmap2.sh"
ok "Launcher script is executable."

# ---- Step 4: Install .desktop file ----
DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"

# Create the .desktop entry with absolute paths
cat > "$DESKTOP_DIR/ezmap2.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=EzMAP2
Comment=Easy Microbiome Analysis Pipeline
Exec=$SCRIPT_DIR/ezmap2.sh
Path=$SCRIPT_DIR
Icon=utilities-terminal
Terminal=false
Categories=Science;Education;Biology;
StartupWMClass=EzMAP2
StartupNotify=true
EOF

chmod +x "$DESKTOP_DIR/ezmap2.desktop"
ok "Desktop entry installed: $DESKTOP_DIR/ezmap2.desktop"

# ---- Step 5: Optional Desktop shortcut ----
if [[ -d "$HOME/Desktop" ]]; then
    cp "$DESKTOP_DIR/ezmap2.desktop" "$HOME/Desktop/EzMAP2.desktop"
    chmod +x "$HOME/Desktop/EzMAP2.desktop"
    # Mark as trusted on GNOME (Ubuntu 22+)
    if command -v gio >/dev/null 2>&1; then
        gio set "$HOME/Desktop/EzMAP2.desktop" metadata::trusted true 2>/dev/null || true
    fi
    ok "Desktop shortcut created: ~/Desktop/EzMAP2.desktop"
fi

echo ""
ok "EzMAP2 installation complete!"
echo "  You can now:"
echo "    • Double-click 'EzMAP2' on your Desktop"
echo "    • Search 'EzMAP2' in the Activities/Application menu"
echo "    • Run from terminal:  $SCRIPT_DIR/ezmap2.sh"
echo ""
