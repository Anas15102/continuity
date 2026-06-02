# Build Plan — Continuity Suite

Complete task checklist for building the macOS ↔ Motorola Smart Connect clone.
Check off tasks as they are completed.

---

## Phase 0 — Environment Setup
- [ ] Install Xcode from Mac App Store
- [ ] Install Homebrew
- [ ] Install android-platform-tools (adb) via Homebrew
- [ ] Install scrcpy via Homebrew
- [ ] Install Android Studio
- [ ] Enable Developer Options on Motorola phone (tap Build Number 7x)
- [ ] Enable USB Debugging on phone
- [ ] Verify ADB connection: `adb devices`
- [ ] Run setup script: `./scripts/setup.sh`

---

## Phase 1 — macOS Project Scaffold
- [ ] Create Xcode project: ContinuityMac (macOS App, SwiftUI, Swift)
- [ ] Add ContinuityCameraExtension target (System Extension)
- [ ] Configure Info.plist: LSUIElement = true (menu bar only app)
- [ ] Configure entitlements:
  - com.apple.security.network.client
  - com.apple.security.network.server
  - com.apple.security.device.bluetooth
  - com.apple.security.files.downloads.read-write
- [ ] Add scrcpy + adb binaries to Resources/Binaries/
- [ ] Set binaries as executable in build phase (chmod +x)

---

## Phase 2 — Core Infrastructure
- [ ] ADBBridge.swift — wrapper around adb binary for all shell commands
- [ ] DeviceDiscovery.swift — mDNS browser using Network.framework
- [ ] AppDelegate.swift — NSStatusItem menu bar icon setup

---

## Phase 3 — UI Layer
- [ ] MenuBarController.swift — NSStatusItem + NSPopover management
- [ ] PopoverView.swift — main Liquid Glass panel (connection pill, toggles, drop zone)
- [ ] MirrorWindowView.swift — dedicated window for screen mirror display
- [ ] ShareHubView.swift — drag-and-drop file transfer panel

---

## Phase 4 — Screen Mirroring & App Streaming
- [ ] MirroringSessionManager.swift — launch/terminate scrcpy process
- [ ] Single-click mirror button wired to manager
- [ ] App streaming mode (--new-display flag)
- [ ] Desktop mode (--new-display=1920x1080/240 --no-vd-system-decorations)
- [ ] Handle process termination and UI state cleanup

---

## Phase 5 — Cross Control
- [ ] PeripheralRoutingEngine.swift — CGEvent tap setup
- [ ] Edge detection (right edge trigger, left edge release)
- [ ] Cursor lock with CGAssociateMouseAndMouseCursorPosition
- [ ] Delta scaling math (Mac resolution → Android resolution)
- [ ] ADB input event forwarding
- [ ] Keyboard event forwarding via ADB
- [ ] ESC key to release control

---

## Phase 6 — Universal Clipboard
- [ ] ClipboardSyncDaemon.swift — NSPasteboard change monitor
- [ ] WebSocket server on port 8765 (NWListener)
- [ ] AES-256-GCM encryption with CryptoKit
- [ ] Send clipboard to Android on change
- [ ] Receive clipboard from Android and write to NSPasteboard

---

## Phase 7 — Share Hub
- [ ] FileTransferEngine.swift — ADB push wrapper
- [ ] SwiftUI drop zone accepting files/images/text
- [ ] Progress indicator during transfer
- [ ] Success/failure notification (UserNotifications)
- [ ] QuickDrop integration (optional, for Quick Share protocol)

---

## Phase 8 — Phone as Webcam
- [ ] VirtualCameraController.swift — scrcpy camera capture process
- [ ] CMIOExtension target: ExtensionProvider.swift
- [ ] CMIOExtension target: VirtualCameraDeviceController.swift
- [ ] CVPixelBuffer pipeline from scrcpy stdout → CMIOExtensionStream
- [ ] System extension activation flow
- [ ] Test in FaceTime / Zoom

---

## Phase 9 — Smart Hotspot
- [ ] HotspotController.swift — ADB shell tethering intent
- [ ] Toggle button in PopoverView
- [ ] Status feedback (on/off state)

---

## Phase 10 — Android Companion APK
- [ ] Create Android Studio project: ContinuityAndroid
- [ ] ContinuityService.kt — foreground service (persistent background)
- [ ] MdnsAdvertiser.kt — advertise _continuity._tcp on port 8765
- [ ] ClipboardSyncReceiver.kt — WebSocket server, write to ClipboardManager
- [ ] NotificationBridge.kt — NotificationListenerService
- [ ] MainActivity.kt — permission grants + service start
- [ ] AndroidManifest.xml — all permissions declared
- [ ] Build APK: `./scripts/build_android.sh`
- [ ] Install on device: `adb install app-debug.apk`

---

## Phase 11 — Polish & Integration
- [ ] Battery level display in popover (adb shell dumpsys battery)
- [ ] Device name display
- [ ] Auto-reconnect on USB plug/unplug (IOKit notification)
- [ ] Wi-Fi connection mode (adb tcpip 5555)
- [ ] Onboarding flow (first launch pairing wizard)
- [ ] App icon + menu bar icon assets
- [ ] Dark/light mode support

---

## Phase 12 — Build & Distribution
- [ ] Run `./scripts/build_mac.sh` — verify clean build
- [ ] Run `./scripts/build_android.sh` — verify APK
- [ ] Test all features end-to-end
- [ ] Code sign (requires Apple Developer account for camera extension)

---

## Known Constraints

| Item | Note |
|---|---|
| Camera Extension | Requires Apple Developer Program ($99/yr) to sign System Extension |
| ADB over Wi-Fi | Run `adb tcpip 5555` once via USB, then unplug |
| scrcpy Desktop Mode | Requires Android 10+ and Developer Options enabled |
| App Sandbox | Some CGEvent tap features may need Accessibility permission grant |
| QuickDrop | Binary must be compiled separately from source |
