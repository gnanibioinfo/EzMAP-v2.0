#!/bin/bash
# =============================================================================
# EzMAP2 Launcher — Double-click or run from terminal
# =============================================================================
# Locates the EzMAP2.jar relative to this script and launches it.
# Ensures Java 11+ is available and sets sensible JVM defaults.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JAR="$SCRIPT_DIR/target/EzMAP2.jar"

# ---- Check JAR exists ----
if [[ ! -f "$JAR" ]]; then
    # Also check if JAR is in the same directory as the script (deployed layout)
    if [[ -f "$SCRIPT_DIR/EzMAP2.jar" ]]; then
        JAR="$SCRIPT_DIR/EzMAP2.jar"
    else
        zenity --error --title="EzMAP2" \
            --text="EzMAP2: JAR not found.\n\nLooked in:\n  $SCRIPT_DIR/target/EzMAP2.jar\n  $SCRIPT_DIR/EzMAP2.jar\n\nPlease build with: bash build.sh" 2>/dev/null \
        || echo "ERROR: EzMAP2: JAR not found. Build with: bash build.sh"
        exit 1
    fi
fi

# ---- Check Java ----
if ! command -v java >/dev/null 2>&1; then
    zenity --error --title="EzMAP2" \
        --text="Java is not installed.\n\nInstall with:\n  sudo apt install default-jdk" 2>/dev/null \
    || echo "ERROR: Java not found. Install with: sudo apt install default-jdk"
    exit 1
fi

# Extract major version from various java -version output formats:
#   openjdk version "17.0.6" ...    → 17
#   java version "1.8.0_362" ...    → 8  (legacy 1.x format)
#   openjdk 11.0.20 2023-07-18 ...  → 11 (some distros omit quotes)
JAVA_VER_RAW=$(java -version 2>&1 | head -1)
JAVA_VER=$(echo "$JAVA_VER_RAW" | sed -n 's/.*version "\{0,1\}\([0-9]\+\).*/\1/p')
# Handle legacy "1.x" format (e.g., "1.8" → 8)
if [[ "$JAVA_VER" == "1" ]]; then
    JAVA_VER=$(echo "$JAVA_VER_RAW" | sed -n 's/.*version "\{0,1\}1\.\([0-9]\+\).*/\1/p')
fi
# Only warn if we successfully parsed a version AND it's below 11
if [[ -n "$JAVA_VER" && "$JAVA_VER" -lt 11 ]] 2>/dev/null; then
    zenity --warning --title="EzMAP2" \
        --text="Java 11+ recommended (found Java $JAVA_VER).\nEzMAP2 may not work correctly." 2>/dev/null \
    || echo "WARNING: Java 11+ recommended (found Java $JAVA_VER)"
fi

# ---- Launch ----
cd "$SCRIPT_DIR"
exec java -Xmx2g -jar "$JAR" "$@"
