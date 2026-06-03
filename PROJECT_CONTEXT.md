# Continuity — Project Context for AI Agents

> This document is for any AI agent or developer picking up this project.
> It covers architecture, what's built, what's broken, and what's planned.

---

## Project Overview

**Continuity** is a free, open-source macOS menu bar app + Android companion app that replicates Apple Continuity features for Android devices. Think "Samsung DeX / Motorola Smart Connect but for any Android phone connecting to a Mac."

- **Repo:** https://github.com/Anas15102/continuity
- **Status:** Beta v0.1 — core features working, some polish needed
- **Owner:** Anas15102

---

## Tech Stack

| Side | Language | Framework | Min Version |
|---|---|---|---|
| Mac | Swift 5 | SwiftUI + AppKit | macOS 13 Ventura |
| Android | Kotlin | Jetpack Compose | Android 10 (API 29) |
| Connection | TCP/TLS | Apple Network.framework / Java SSLSocket | — |
| Discovery | mDNS | NWBrowser (Mac) / NSD (Android) | — |
| Screen Mirror | scrcpy | ADB | — |

---

## Project Structure

```
smart/
├── ARCHITECTURE.md              ← System architecture overview
├── PLAN.md                      ← Original build plan
├── PROJECT_CONTEXT.md           ← THIS FILE
├── README.md                    ← Public-facing README
├── release.sh                   ← GitHub release script
│
├── ContinuityMac/               ← Xcode project (macOS app)
│   └── ContinuityMac/
│       ├── App/
│       │   ├── AppDelegate.swift          ← Menu bar setup, service lifecycle
│       │   └── ContinuityMacApp.swift     ← @main entry point
│       ├── Core/
│       │   ├── ADBBridge.swift            ← Wrapper around embedded adb binary
│       │   ├── CallBridge.swift           ← Call management, floating banner window
│       │   ├── ClipboardSyncDaemon.swift  ← TCP client, TLS, identity exchange, clipboard sync
│       │   ├── DeviceDiscovery.swift      ← mDNS browser + ADB polling
│       │   ├── FileTransferEngine.swift   ← ADB push file transfer
│       │   ├── HotspotController.swift    ← Toggle phone hotspot via ADB
│       │   ├── MirroringSessionManager.swift ← scrcpy wrapper
│       │   ├── NotificationBridge.swift   ← Receives notifs, shows on Mac with reply
│       │   ├── PairingManager.swift       ← Saves paired devices, auto-connect
│       │   ├── PeripheralRoutingEngine.swift ← Cross Control (mouse/keyboard)
│       │   └── WifiConnectionManager.swift   ← ADB Wi-Fi mode switcher
│       ├── UI/
│       │   ├── AppStreamView.swift        ← App picker (NOT in popover, kept for future)
│       │   ├── CallBannerView.swift       ← Floating bottom-right call window
│       │   ├── MirrorWindowView.swift     ← Screen mirror window
│       │   ├── NotificationsView.swift    ← Notifications sheet
│       │   ├── PairingView.swift          ← QR scanner + manual IP pairing
│       │   ├── PopoverView.swift          ← Main menu bar popover UI
│       │   └── ShareHubView.swift         ← Drag & drop file transfer zone
│       └── Resources/
│           ├── Binaries/adb               ← Embedded adb binary
│           ├── Binaries/scrcpy            ← Embedded scrcpy binary
│           └── ContinuityMac.entitlements ← App sandbox entitlements
│
└── ContinuityAndroid/           ← Android Studio project
    └── app/src/main/
        ├── AndroidManifest.xml
        └── java/com/continuity/android/
            ├── CallActionHandler.kt       ← Handles answer/decline/hangup from Mac
            ├── ClipboardSyncReceiver.kt   ← Two-way clipboard via ClipboardManager listener
            ├── ConnectionManager.kt       ← TLS TCP server, identity exchange, pairing
            ├── ContinuityService.kt       ← Foreground service, wires everything together
            ├── MainActivity.kt            ← UI: shows QR code, connection status
            ├── MdnsAdvertiser.kt          ← Advertises on local network via NSD
            ├── MessageReplyHandler.kt     ← Routes replies to SMS/WhatsApp/Telegram
            ├── NotificationBridge.kt      ← NotificationListenerService, forwards to Mac
            ├── QRGenerator.kt             ← ZXing QR code generator for pairing
            └── TLSManager.kt             ← BouncyCastle self-signed cert generation
```

---

## Connection Architecture

```
Android (TCP TLS Server :9876)
    │
    ├── Advertises via mDNS (_continuity._tcp.)
    ├── Generates self-signed TLS cert on first run (BouncyCastle)
    ├── Shows QR code with pairing URL: continuity://pair?ip=X&port=9876&name=Device
    │
    ↕  TLS TCP connection
    │
Mac (TCP TLS Client)
    │
    ├── Discovers Android via mDNS OR scans QR code
    ├── Saves paired devices to UserDefaults
    ├── Auto-connects on launch to saved devices
    └── ADB fallback for USB-connected devices
```

### Packet Format
All packets use a 4-byte big-endian length prefix followed by a JSON payload:
```
[4 bytes: payload length] [N bytes: UTF-8 JSON]
```

### Message Types
| type | direction | payload fields |
|---|---|---|
| `identity` | both → both | deviceName, deviceId, deviceType, appVersion, capabilities[] |
| `clipboard` | both → both | text |
| `notification` | Android → Mac | app, title, body, replyable |
| `sms` | Android → Mac | sender, body |
| `call_incoming` | Android → Mac | caller, number |
| `call_answered` | Android → Mac | (no extra fields) |
| `call_ended` | Android → Mac | (no extra fields) |
| `call_action` | Mac → Android | action: "answer"/"decline"/"hangup" |
| `reply` | Mac → Android | to, message, app |
| `sms_send` | Mac → Android | to, message |
| `ping` | Mac → Android | (no extra fields) |
| `pong` | Android → Mac | (no extra fields) |

### Pairing Flow
1. Android runs → shows QR code containing `continuity://pair?ip=X&port=9876&name=Model`
2. Mac clicks "Pair New Device" → opens QR scanner (PairingView.swift)
3. QR scanned → PairingManager saves device to UserDefaults
4. On next launch, Mac auto-connects to all saved devices via PairingManager.autoConnect()
5. On connect: TLS handshake → identity exchange → if new Mac, Android shows "Accept/Reject" notification

---

## What's Built & Working

### ✅ Core Infrastructure
- TLS-encrypted TCP connection (self-signed certs, trust-on-first-use like KDEConnect)
- Identity exchange on every connect (device name, capabilities negotiation)
- Pairing system with QR code (PairingView + QRGenerator)
- Pairing confirmation on Android (Accept/Reject notification)
- Auto-reconnect with 5s backoff
- Auto-connect to saved devices on launch
- mDNS discovery on both sides
- ADB/USB fallback

### ✅ Clipboard Sync
- Mac → Android: NSPasteboard poll every 0.8s → TCP send
- Android → Mac: ClipboardManager.OnPrimaryClipChangedListener → TCP send
- Echo loop prevention (lastMacContent / lastAndroidContent tracking)
- Works on Android 10+ via ClipboardManager listener (no ADB needed)

### ✅ Notifications + Messaging
- All Android app notifications forwarded to Mac as native macOS notifications
- Messaging apps (WhatsApp, SMS, Telegram, Instagram, Signal, Discord etc.) show with **Reply** button
- Inline reply from macOS notification → routes back to correct app on Android
- ADB polling fallback when companion app not connected

### ✅ Calls
- Incoming call → floating bottom-right banner (non-blocking)
- Answer / Decline buttons on the banner
- Active call: live timer, Hangup button
- Reply with SMS from the call banner
- Auto-dismiss when call answered or ended on phone
- ADB polling fallback for call state detection

### ✅ Screen Mirroring
- Uses scrcpy (embedded binary in app bundle)
- MirroringSessionManager wraps scrcpy process
- Opens in a separate window (MirrorWindowView)

### ✅ File Transfer (Share Hub)
- Drag files from Finder into the popover drop zone
- Uses native NSView drag destination (fixes popover closing bug)
- ADB push to /sdcard/Download/

### ✅ Cross Control (Mouse & Keyboard)
- Move mouse to right edge of Mac screen → routes input to Android
- Uses CGEvent tap (requires Accessibility permission)
- Move to left edge or press ESC to release
- Sends `input motionevent` and `input keyevent` via ADB

### ✅ Smart Hotspot
- Toggle phone's hotspot via ADB intent

### ✅ App UI
- Menu bar only (NSStatusItem, .accessory activation policy)
- Popover with: device header, battery, Wi-Fi/USB status, feature toggles, Share Hub
- Dark frosted glass design (NSVisualEffectView)
- Scrollable content (nothing gets cut off)
- Quit button (red pill, bottom of popover)

### ✅ GitHub
- Repo live at github.com/Anas15102/continuity
- DMG release at github.com/Anas15102/continuity/releases/tag/v0.1-beta
- MIT license

---

## Known Issues / Bugs

### Mac App
- **PairingView + PairingManager not in Xcode project** — these files exist on disk but need to be manually added in Xcode (right-click Core folder → Add Files, right-click UI folder → Add Files)
- **Cross Control event tap** needs Accessibility permission — app opens System Settings automatically if not granted but UX could be smoother
- **Call audio** — answering routes the keyevent to the phone but voice audio does NOT come through the Mac. Audio bridging over TCP is not yet implemented.
- **Screen mirroring** may not work if scrcpy binary path is wrong — check Resources/Binaries/scrcpy exists and is executable

### Android App
- **TLSManager** uses BouncyCastle which adds ~3MB to APK — consider switching to Android KeyStore API for cert generation in production
- **ANSWER_PHONE_CALLS** permission only works on Android 8+ and may require the app to be set as default phone app on some ROMs
- **MessageReplyHandler** direct SMS send requires SEND_SMS permission which some users may deny — intent fallback opens the messaging app instead

---

## Planned / Future Features

### High Priority
- [ ] **Audio bridge for calls** — stream mic/speaker over TCP so voice works through Mac (complex, needs low-latency audio pipeline, ~20ms target)
- [ ] **Notification dismissal sync** — when user dismisses notification on Mac, also dismiss on phone
- [ ] **Battery polling** — show live battery % in menu bar popover (ADB: `dumpsys battery | grep level`)
- [ ] **Bluetooth audio HFP** — use CoreBluetooth + Android's BluetoothHeadset profile for call audio without needing TCP audio stream
- [ ] **Android → Mac file send** — currently only Mac → Android. Add Android share sheet option that sends files via TCP to Mac.

### Medium Priority
- [ ] **App icon** — needs a proper icon (.icns for Mac, adaptive icon for Android)
- [ ] **onboarding flow** — first-launch wizard on both platforms showing setup steps
- [ ] **Multiple paired devices** — PairingManager supports it in code but UI only shows first device
- [ ] **Connection status in popover** — "Connected via Wi-Fi · 192.168.1.5" or "Connected via USB"
- [ ] **Auto-start on login** — LaunchAgent plist on Mac, BOOT_COMPLETED receiver on Android
- [ ] **Clipboard history** — show last 5 synced clipboard items in popover

### Low Priority / Nice to Have
- [ ] **Virtual camera (phone as webcam)** — ContinuityCameraExtension skeleton exists, needs AVCaptureDevice streaming from Android over TCP
- [ ] **Desktop mode** — AppStreamView and MirroringSessionManager.desktop mode partially built
- [ ] **macOS Notification Center widget** — show phone battery + recent notifs without opening popover
- [ ] **iMessage integration** — use phone's iMessage account? (legally grey)
- [ ] **End-to-end encryption** — currently TLS only; add AES-256-GCM payload encryption as extra layer
- [ ] **App Store distribution** — requires $99/year Apple Developer account + notarization
- [ ] **Windows Mac** — port Mac side to Windows (Electron or .NET MAUI)

---

## Development Setup

### Mac App
```bash
# Open in Xcode
open ContinuityMac/ContinuityMac.xcodeproj

# Build from CLI
xcodebuild -project "ContinuityMac/ContinuityMac.xcodeproj" \
           -scheme ContinuityMac build

# Build DMG
xcodebuild ... -configuration Release -archivePath /tmp/app.xcarchive archive
hdiutil create -volname "Continuity" -srcfolder /tmp/dmg-staging -format UDZO Continuity.dmg
```

### Android App
```bash
cd ContinuityAndroid
./gradlew assembleDebug
adb install app/build/outputs/apk/debug/app-debug.apk
```

### Required Permissions (Android)
The user must manually enable:
1. **Notification Access** — Settings → Apps → Special app access → Notification access → Continuity
2. **Accessibility** — NOT needed on Android (only Mac needs this for Cross Control)

The app requests at runtime:
- POST_NOTIFICATIONS (Android 13+)
- SEND_SMS
- READ_PHONE_STATE

### Required Permissions (Mac)
- **Accessibility** — for Cross Control (CGEvent tap). App opens System Settings automatically.
- **Camera** — for QR pairing scanner in PairingView
- **Notifications** — requested on first launch

---

## Entitlements (Mac)
File: `ContinuityMac/ContinuityMac/Resources/ContinuityMac.entitlements`
```xml
com.apple.security.app-sandbox = false   (NOT sandboxed — needed for ADB, CGEvent tap)
com.apple.security.device.bluetooth = true
com.apple.security.files.downloads.read-write = true
com.apple.security.files.user-selected.read-write = true
com.apple.security.network.client = true
com.apple.security.network.server = true
```

Note: App is NOT sandboxed. This is intentional — sandbox would block ADB, CGEvent taps, and the camera extension. This is why it can't go on the Mac App Store without significant rework.

---

## Coding Conventions

### Swift (Mac)
- `ObservableObject` + `@Published` for all state that SwiftUI needs to observe
- Singletons via `static let shared = ...` + `private init()`
- All network ops on background queues, UI updates on `DispatchQueue.main`
- `NWConnection` / `NWBrowser` from Network.framework (NOT URLSession or raw sockets)
- Packet format: 4-byte big-endian length prefix + UTF-8 JSON

### Kotlin (Android)
- `object` for singletons
- `thread {}` for background work (no coroutines yet — could migrate)
- All UI updates via `Handler(Looper.getMainLooper()).post {}`
- Same packet format as Mac side

### Packet JSON convention
- All packets have a `"type"` string field
- Snake_case for field names
- No nulls — use empty string `""` instead

---

## Git / Release

```bash
# Push changes
git add -A
git commit -m "description"
git push

# Create GitHub release with DMG
gh release create v0.X-beta \
  --repo Anas15102/continuity \
  --title "Continuity vX.X" \
  --notes "Release notes here" \
  --prerelease \
  /path/to/ContinuityMac.dmg

# Upload APK to existing release
gh release upload v0.X-beta /path/to/app-debug.apk \
  --repo Anas15102/continuity
```

---

## Dependencies

### Mac
- No external Swift packages — uses only Apple frameworks:
  - SwiftUI, AppKit, Foundation, Network, AVFoundation, CoreGraphics, UserNotifications, CryptoKit, ApplicationServices

### Android
```groovy
// app/build.gradle
implementation platform('androidx.compose:compose-bom:2024.02.00')
implementation 'androidx.compose.material3:material3'
implementation 'androidx.activity:activity-compose:1.8.2'
implementation 'androidx.core:core-ktx:1.12.0'
implementation 'androidx.lifecycle:lifecycle-runtime-ktx:2.7.0'
implementation 'com.google.zxing:core:3.5.3'          // QR code generation
implementation 'org.bouncycastle:bcpkix-jdk15to18:1.78.1'  // TLS cert generation
```

---

## Important Notes for AI Agents

1. **The Xcode project file (`project.pbxproj`) does NOT auto-update** when you create new `.swift` files on disk. Any new Swift files must be added to the Xcode project manually (right-click folder in Xcode → Add Files) OR the pbxproj must be edited programmatically. This has caused build failures in the past.

2. **The iCloud Drive path has spaces** — the project lives at `/Users/anas/Library/Mobile Documents/com~apple~CloudDocs/smart/`. All CLI commands must quote this path properly.

3. **`gh` CLI requires `~/.config/gh/` to be writable** — was broken due to permissions. Fixed with `sudo chown -R anas /Users/anas/.config`. If auth fails again, run that command first.

4. **Android TLSManager requires BouncyCastle** — if BouncyCastle causes conflicts with the Android runtime's built-in BC provider, add `Security.removeProvider("BC")` before `Security.addProvider(BouncyCastleProvider())` in TLSManager.init().

5. **ClipboardSyncDaemon is the central hub** — it manages the TLS TCP connection AND routes all non-clipboard messages (notifications, calls, replies) to their respective handlers. If the connection is broken, everything stops working.

6. **Don't use ADB for clipboard on Android 10+** — `cmd clipboard get-text` and `cmd clipboard set-text` are blocked/unreliable on modern Android. The companion app's ClipboardManager listener is the only reliable method.

7. **popover `.semitransient` behavior** — the popover must stay as `.semitransient` (not `.transient`) or it closes when the user tries to drag files into the Share Hub drop zone.
