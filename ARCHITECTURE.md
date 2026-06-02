# System Architecture — Continuity Suite

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    macOS SwiftUI App Bundle                     │
│                                                                 │
│  ┌─────────────────┐    ┌──────────────────────────────────┐   │
│  │  SwiftUI UI      │    │   Continuous Discovery Daemon    │   │
│  │  Liquid Glass    │    │   (mDNS / Network.framework)     │   │
│  └────────┬────────┘    └──────────────┬───────────────────┘   │
│           │                            │                        │
│           └──────────────┬─────────────┘                        │
│                          ▼                                      │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                 App Coordination Layer                    │  │
│  │              (AppDelegate + Feature Managers)             │  │
│  └──────┬──────────────┬──────────────┬──────────────┬──────┘  │
│         │              │              │              │          │
│         ▼              ▼              ▼              ▼          │
│  ┌────────────┐ ┌────────────┐ ┌──────────┐ ┌────────────────┐ │
│  │  scrcpy    │ │ FileXfer   │ │Clipboard │ │ CMIOExtension  │ │
│  │  Process   │ │ (ADB push) │ │ Daemon   │ │ (Webcam)       │ │
│  └─────┬──────┘ └─────┬──────┘ └────┬─────┘ └───────┬────────┘ │
└────────┼──────────────┼─────────────┼───────────────┼──────────┘
         │              │             │               │
         └──────────────┴──────┬──────┴───────────────┘
                               ▼
              ┌────────────────────────────────┐
              │         Android Device          │
              │  ┌──────────────────────────┐  │
              │  │  ContinuityService (APK) │  │
              │  │  mDNS + WebSocket + NLS  │  │
              │  └──────────────────────────┘  │
              └────────────────────────────────┘
```

---

## Transport Layers

| Feature | Transport | Protocol | Port |
|---|---|---|---|
| Screen Mirror | USB / Wi-Fi TCP | ADB tunnel → H.265 | 27183 (scrcpy) |
| App Streaming | USB / Wi-Fi TCP | ADB tunnel → H.265 | 27183 (scrcpy) |
| Desktop Mode | USB / Wi-Fi TCP | ADB tunnel → H.265 | 27183 (scrcpy) |
| Cross Control | ADB shell | input events | via ADB |
| Clipboard | Local Wi-Fi | WebSocket + AES-GCM | 8765 |
| File Share | USB / Wi-Fi | ADB push / Quick Share | via ADB |
| Webcam | USB / Wi-Fi TCP | ADB tunnel → H.265 | 27183 (scrcpy) |
| Notifications | Local Wi-Fi | WebSocket + AES-GCM | 8765 |
| Discovery | Local Wi-Fi | mDNS / Bonjour | multicast |

---

## Security Model

- All WebSocket traffic encrypted with AES-256-GCM (CryptoKit)
- Device pairing uses public key exchange on first connect
- Trusted device ID stored in macOS Keychain
- ADB connection authenticated by Android's RSA key system
- No cloud servers — fully local network only
- Tailscale VPN supported as fallback for remote access

---

## Cross Control Physics

```
Mac display: Wmac × Hmac
Android display: Wand × Hand
Trigger zone: δ = 2px from right edge

Transition: ACTIVE if x ≥ Wmac - δ AND Δx > 0

When ACTIVE:
  CGAssociateMouseAndMouseCursorPosition(false)  // lock cursor
  
  xand_new = xand_prev + (Δx × (Wand / Wmac) × λ)
  yand_new = yand_prev + (Δy × (Hand / Hmac) × λ)
  
  where λ = pointer acceleration scale factor (default 1.0)

Release: left edge OR ESC key
  CGAssociateMouseAndMouseCursorPosition(true)   // unlock cursor
```

---

## Webcam Pipeline

```
Android Camera (YUV)
       │
       ▼ scrcpy --video-source=camera
ADB Socket Tunnel (H.265 stream)
       │
       ▼ VideoToolbox decode
CVPixelBuffer (BGRA)
       │
       ▼ Metal GPU filter (optional)
CMIOExtensionStream.send(sampleBuffer)
       │
       ▼
macOS Virtual Camera Device
       │
       ▼
FaceTime / Zoom / OBS / Safari
```

---

## Android Companion Service

```
ContinuityService (Foreground Service)
├── MdnsAdvertiser
│   └── Advertises _continuity._tcp on port 8765
├── WebSocketServer (port 8765)
│   ├── Receives clipboard payloads → ClipboardManager
│   └── Sends clipboard changes → Mac
└── NotificationBridge (NotificationListenerService)
    └── Forwards notification payloads → Mac via WebSocket
```
