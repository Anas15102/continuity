import Cocoa
import CoreGraphics
import ApplicationServices

/// Cross Control — seamless mouse and keyboard routing to the Android device.
///
/// Trigger: move cursor to the right edge of the Mac screen
/// Release: move cursor back to the left edge, or press ESC
///
/// Requires: Accessibility permission (System Settings → Privacy → Accessibility)
final class PeripheralRoutingEngine: ObservableObject {
    static let shared = PeripheralRoutingEngine()
    private init() {}

    // MARK: - Published State

    @Published var isCursorRoutingActive = false
    @Published var permissionDenied = false

    // MARK: - Android Target Resolution

    private var androidWidth: CGFloat = 1080
    private var androidHeight: CGFloat = 2400

    // Current virtual cursor position on Android screen
    private var androidCursorX: CGFloat = 540
    private var androidCursorY: CGFloat = 1200

    // MARK: - Event Tap

    private var inputEventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var edgeMonitor: Any?
    private var eventTapThread: Thread?

    // MARK: - Public API

    func initializeCursorTracker() {
        // Check Accessibility permission first
        guard checkAccessibilityPermission() else {
            DispatchQueue.main.async {
                self.permissionDenied = true
                self.isCursorRoutingActive = false
            }
            // Open System Settings to the right pane
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
            print("[CrossControl] Accessibility permission required. Opening System Settings.")
            return
        }

        permissionDenied = false
        fetchAndroidResolution()

        guard let screen = NSScreen.main else { return }
        let triggerX = screen.frame.size.width - 3.0

        edgeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self = self, !self.isCursorRoutingActive else { return }
            let loc = NSEvent.mouseLocation
            if loc.x >= triggerX {
                self.activateControlRouting()
            }
        }

        print("[CrossControl] Edge monitor active — move mouse to right edge.")
    }

    func releaseControl() {
        deactivateControlRouting()
        if let monitor = edgeMonitor {
            NSEvent.removeMonitor(monitor)
            edgeMonitor = nil
        }
        DispatchQueue.main.async { self.isCursorRoutingActive = false }
        print("[CrossControl] Control released.")
    }

    // MARK: - Accessibility Check

    private func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Activation / Deactivation

    private func activateControlRouting() {
        guard !isCursorRoutingActive else { return }
        guard checkAccessibilityPermission() else {
            DispatchQueue.main.async { self.permissionDenied = true }
            return
        }

        DispatchQueue.main.async { self.isCursorRoutingActive = true }

        // Lock hardware cursor
        CGAssociateMouseAndMouseCursorPosition(boolean_t(0))

        // Reset Android cursor to center
        androidCursorX = androidWidth / 2
        androidCursorY = androidHeight / 2

        let eventMask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        inputEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let engine = Unmanaged<PeripheralRoutingEngine>.fromOpaque(refcon).takeUnretainedValue()
                return engine.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        )

        guard let tap = inputEventTap else {
            print("[CrossControl] Failed to create event tap — check Accessibility permission.")
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
            DispatchQueue.main.async { self.isCursorRoutingActive = false }
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        // Run the event tap on a dedicated thread so it doesn't block the main RunLoop
        let tapSource = runLoopSource!
        eventTapThread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), tapSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        eventTapThread?.name = "CrossControlEventTap"
        eventTapThread?.start()

        print("[CrossControl] Input routing active.")
    }

    private func deactivateControlRouting() {
        if let tap = inputEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            inputEventTap = nil
        }
        if let source = runLoopSource {
            // Stop the dedicated run loop
            CFRunLoopStop(CFRunLoopGetCurrent())
            runLoopSource = nil
        }
        eventTapThread?.cancel()
        eventTapThread = nil
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
    }

    // MARK: - Event Handler

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let screen = NSScreen.main else { return Unmanaged.passRetained(event) }

        switch type {
        case .mouseMoved:
            let dx = event.getIntegerValueField(.mouseEventDeltaX)
            let dy = event.getIntegerValueField(.mouseEventDeltaY)

            let scaleX = androidWidth / screen.frame.width
            let scaleY = androidHeight / screen.frame.height

            androidCursorX += CGFloat(dx) * scaleX
            androidCursorY += CGFloat(dy) * scaleY

            androidCursorX = max(0, min(androidWidth, androidCursorX))
            androidCursorY = max(0, min(androidHeight, androidCursorY))

            // Release when cursor reaches left edge of Android screen
            if androidCursorX <= 0 {
                DispatchQueue.global(qos: .userInteractive).async { self.releaseControl() }
                return Unmanaged.passRetained(event)
            }

            transmitMouseMove(x: Int(androidCursorX), y: Int(androidCursorY))
            return nil  // consume — don't pass to macOS

        case .leftMouseDown:
            transmitTap(x: Int(androidCursorX), y: Int(androidCursorY), isDown: true)
            return nil

        case .leftMouseUp:
            transmitTap(x: Int(androidCursorX), y: Int(androidCursorY), isDown: false)
            return nil

        case .rightMouseDown:
            // Right click → Android long press
            transmitLongPress(x: Int(androidCursorX), y: Int(androidCursorY))
            return nil

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 53 { // ESC
                DispatchQueue.global(qos: .userInteractive).async { self.releaseControl() }
                return nil
            }
            // Try to get the actual character for text input
            if let chars = event.unescapedCharacters, !chars.isEmpty, chars.unicodeScalars.first!.value < 128 {
                transmitText(chars)
            } else {
                transmitKeyEvent(keyCode: Int(keyCode))
            }
            return nil

        case .scrollWheel:
            let delta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            transmitScroll(delta: Int(delta))
            return nil

        default:
            return Unmanaged.passRetained(event)
        }
    }

    // MARK: - ADB Transmission

    /// Move the pointer (requires Android 9+ — uses absolute positioning via `input motionevent`)
    private func transmitMouseMove(x: Int, y: Int) {
        // Throttle: only send every other event to avoid ADB saturation
        DispatchQueue.global(qos: .userInteractive).async {
            ADBBridge.shared.shell("input motionevent HOVER_MOVE \(x) \(y)")
        }
    }

    private func transmitTap(x: Int, y: Int, isDown: Bool) {
        DispatchQueue.global(qos: .userInteractive).async {
            if isDown {
                ADBBridge.shared.shell("input motionevent DOWN \(x) \(y)")
            } else {
                ADBBridge.shared.shell("input motionevent UP \(x) \(y)")
                // Also send a tap as some apps need both
                ADBBridge.shared.shell("input tap \(x) \(y)")
            }
        }
    }

    private func transmitLongPress(x: Int, y: Int) {
        DispatchQueue.global(qos: .userInteractive).async {
            ADBBridge.shared.shell("input swipe \(x) \(y) \(x) \(y) 800")
        }
    }

    private func transmitText(_ text: String) {
        let safe = text
            .replacingOccurrences(of: " ", with: "%s")
            .replacingOccurrences(of: "'", with: "\\'")
        DispatchQueue.global(qos: .userInteractive).async {
            ADBBridge.shared.shell("input text '\(safe)'")
        }
    }

    private func transmitKeyEvent(keyCode: Int) {
        let androidCode = mapMacKeyToAndroid(keyCode)
        DispatchQueue.global(qos: .userInteractive).async {
            ADBBridge.shared.shell("input keyevent \(androidCode)")
        }
    }

    private func transmitScroll(delta: Int) {
        let cx = Int(androidCursorX)
        let cy = Int(androidCursorY)
        let endY = cy - (delta * 60)
        DispatchQueue.global(qos: .userInteractive).async {
            ADBBridge.shared.shell("input swipe \(cx) \(cy) \(cx) \(endY) 120")
        }
    }

    // MARK: - Resolution Fetch

    private func fetchAndroidResolution() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            let output = ADBBridge.shared.shell("wm size")
            if let range = output.range(of: #"\d+x\d+"#, options: .regularExpression) {
                let parts = output[range].components(separatedBy: "x")
                if parts.count == 2,
                   let w = Double(parts[0]), let h = Double(parts[1]) {
                    DispatchQueue.main.async {
                        self?.androidWidth = CGFloat(w)
                        self?.androidHeight = CGFloat(h)
                        print("[CrossControl] Android resolution: \(w)x\(h)")
                    }
                }
            }
        }
    }

    // MARK: - Key Map

    private func mapMacKeyToAndroid(_ mac: Int) -> Int {
        let map: [Int: Int] = [
            0: 29,   // A
            1: 47,   // S
            2: 32,   // D
            3: 34,   // F
            4: 35,   // H
            5: 36,   // G
            6: 54,   // Z
            7: 53,   // X
            8: 31,   // C
            9: 50,   // V
            11: 48,  // B
            12: 46,  // Q
            13: 51,  // W
            14: 33,  // E
            15: 46,  // R
            17: 49,  // T
            16: 44,  // Y
            32: 45,  // U
            34: 37,  // I
            31: 43,  // O
            35: 44,  // P
            36: 66,  // Return
            48: 61,  // Tab
            49: 62,  // Space
            51: 67,  // Delete/Backspace
            53: 111, // ESC → BACK
            117: 112,// Forward delete
            123: 21, // Left arrow
            124: 22, // Right arrow
            125: 20, // Down arrow
            126: 19, // Up arrow
        ]
        return map[mac] ?? 0
    }
}

// MARK: - CGEvent Helper

private extension CGEvent {
    /// Returns the printable characters for a key down event.
    var unescapedCharacters: String? {
        let maxLength = 4
        var length = 0
        var chars = [UniChar](repeating: 0, count: maxLength)
        self.keyboardGetUnicodeString(maxStringLength: maxLength, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: Array(chars.prefix(length)), count: length)
    }
}
