# Continuity — Android ↔ Mac Bridge

> **Beta** — First app of its kind to bring Apple Continuity-style features to Android on macOS.

Continuity is a free, open-source menu bar app that connects your Android phone to your Mac — clipboard sync, screen mirroring, file sharing, notification mirror, cross-control (shared mouse & keyboard), and more. No cables required.

---

## Screenshots

> Coming soon — beta release

---

## Features

| Feature | Status |
|---|---|
| 📋 Universal Clipboard | ✅ Working |
| 📱 Screen Mirror | ✅ Working |
| 🖱️ Cross Control (mouse & keyboard) | ✅ Working |
| 📂 File Drop (drag to send) | ✅ Working |
| 🔔 Notification Mirror | ✅ Working |
| 📞 Call Alerts on Mac | ✅ Working |
| 🌐 Smart Hotspot | ✅ Working |
| 📡 Wi-Fi + USB support | ✅ Working |
| 🔋 Battery indicator | ✅ Working |

---

## Download

### macOS App (Intel + Apple Silicon)
👉 **[Download ContinuityMac.dmg](https://github.com/Anas15102/continuity/releases/latest)**

### Android Companion App
👉 **[Download Continuity.apk](https://github.com/Anas15102/continuity/releases/latest)**

> Minimum: macOS 13 Ventura · Android 10+

---

## Quick Setup

### On your Mac
1. Download and open `ContinuityMac.dmg`
2. Drag `Continuity.app` to Applications
3. Launch it — the menu bar icon appears
4. If Cross Control doesn't activate: go to **System Settings → Privacy → Accessibility** and allow Continuity

### On your Android phone
1. Download and install `Continuity.apk`  
   *(You may need to enable "Install from unknown sources" in Settings → Security)*
2. Open the app and tap **Start Service**
3. Note your phone's IP address shown on screen
4. Make sure your phone and Mac are on the **same Wi-Fi network**

### Connect
- They auto-connect via mDNS (Bonjour) — usually within 5 seconds
- If not: both devices must be on the same Wi-Fi network
- USB also works — plug in and enable USB debugging

---

## How it works

```
Android Companion App (TCP server :9876)
        ↕  mDNS / Wi-Fi / USB
ContinuityMac (menu bar app, TCP client)
```

- Android runs a foreground service that advertises itself on the local network
- Mac discovers it via mDNS (Bonjour) and connects over TCP
- All features communicate over this single persistent connection
- USB fallback uses ADB for anything not supported over Wi-Fi

---

## Building from Source

### Mac App
```bash
# Requires Xcode 15+ and macOS 13+
cd ContinuityMac
open ContinuityMac.xcodeproj
# Press Cmd+R to build and run
```

### Android App
```bash
# Requires Android Studio or Gradle
cd ContinuityAndroid
./gradlew assembleDebug
# APK output: app/build/outputs/apk/debug/app-debug.apk
adb install app/build/outputs/apk/debug/app-debug.apk
```

---

## Why not on the App Store?

Apple charges $99/year for a developer account to distribute on the Mac App Store. This app is free and open-source. You can:
- Download the DMG directly from the Releases page
- Build from source yourself
- Support the project so it can eventually get signed & notarized

---

## Support the Project ☕

This is a solo project built for free. If it saves you time or you just think it's cool:

- ⭐ Star this repo
- 🐛 [Report bugs](https://github.com/Anas15102/continuity/issues)
- 💬 [Share feedback](https://github.com/Anas15102/continuity/discussions)
- ☕ **[Buy me a coffee](https://buymeacoffee.com/Anas15102)** — helps keep development going

---

## Requirements

- macOS 13.0 Ventura or later
- Android 10 (API 29) or later
- Same Wi-Fi network for wireless mode, OR USB cable with ADB debugging

---

## License

MIT — free to use, modify, and distribute.

---

*Made with ❤️ — because Android users deserve continuity too.*
