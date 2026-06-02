#!/bin/zsh
# setup.sh — Install all dependencies for Continuity Suite

set -e

echo "================================================"
echo "  Continuity Suite — Dependency Setup"
echo "================================================"

# ── Homebrew ──────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  echo "→ Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  echo "✓ Homebrew already installed"
fi

# ── ADB ───────────────────────────────────────────────
if ! command -v adb &>/dev/null; then
  echo "→ Installing android-platform-tools (adb)..."
  brew install android-platform-tools
else
  echo "✓ adb already installed: $(adb version | head -1)"
fi

# ── scrcpy ────────────────────────────────────────────
if ! command -v scrcpy &>/dev/null; then
  echo "→ Installing scrcpy..."
  brew install scrcpy
else
  echo "✓ scrcpy already installed: $(scrcpy --version | head -1)"
fi

# ── ffmpeg ────────────────────────────────────────────
if ! command -v ffmpeg &>/dev/null; then
  echo "→ Installing ffmpeg..."
  brew install ffmpeg
else
  echo "✓ ffmpeg already installed"
fi

# ── Copy binaries into app bundle resources ───────────
BINARIES_DIR="ContinuityMac/ContinuityMac/Resources/Binaries"
mkdir -p "$BINARIES_DIR"

ADB_PATH=$(which adb)
SCRCPY_PATH=$(which scrcpy)

echo "→ Copying adb binary to Resources/Binaries/"
cp "$ADB_PATH" "$BINARIES_DIR/adb"
chmod +x "$BINARIES_DIR/adb"

echo "→ Copying scrcpy binary to Resources/Binaries/"
cp "$SCRCPY_PATH" "$BINARIES_DIR/scrcpy"
chmod +x "$BINARIES_DIR/scrcpy"

# Copy scrcpy-server.jar (required by scrcpy)
SCRCPY_SERVER=$(find /opt/homebrew /usr/local -name "scrcpy-server" 2>/dev/null | head -1)
if [ -n "$SCRCPY_SERVER" ]; then
  cp "$SCRCPY_SERVER" "$BINARIES_DIR/scrcpy-server"
  echo "✓ Copied scrcpy-server"
fi

echo ""
echo "================================================"
echo "  Setup complete!"
echo ""
echo "  Next steps:"
echo "  1. Open ContinuityMac/ContinuityMac.xcodeproj in Xcode"
echo "  2. Connect your Motorola phone via USB"
echo "  3. Run: adb devices  (verify phone is listed)"
echo "  4. Build & run the app in Xcode"
echo "================================================"
