#!/bin/bash
set -e

echo "=== Continuity Release Script ==="

# Install gh CLI if needed
if ! command -v gh &> /dev/null; then
    echo "Installing GitHub CLI..."
    /opt/homebrew/bin/brew install gh
fi

# Check auth
echo "Checking GitHub auth..."
gh auth status 2>&1 || {
    echo "Not logged in. Running: gh auth login"
    gh auth login
}

# Create release
echo "Creating GitHub release v0.1-beta..."
gh release create v0.1-beta \
  --repo Anas15102/continuity \
  --title "Continuity v0.1 Beta" \
  --notes "## Continuity v0.1 Beta

First public beta. Android ↔ Mac continuity features:

- 📋 Two-way clipboard sync over Wi-Fi
- 📱 Screen mirroring  
- 🖱️ Cross Control (mouse & keyboard)
- 📂 File drop
- 🔔 Notification + call mirror
- 🌐 Smart Hotspot

**Setup:** Download DMG → drag to Applications → install Android APK from source.

Both devices must be on the same Wi-Fi network.

macOS security warning on first launch: right-click → Open to bypass.

[☕ Buy me a coffee](https://buymeacoffee.com/Anas15102)" \
  --prerelease \
  "/tmp/ContinuityMac-v0.1-beta.dmg"

echo ""
echo "✅ Done! Visit: https://github.com/Anas15102/continuity/releases"
