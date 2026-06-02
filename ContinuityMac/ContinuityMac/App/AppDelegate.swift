import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Menu Bar
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    // MARK: - Feature Managers
    let adb             = ADBBridge.shared
    let discovery       = DeviceDiscovery.shared
    let mirroring       = MirroringSessionManager.shared
    let crossControl    = PeripheralRoutingEngine.shared
    let clipboard       = ClipboardSyncDaemon.shared
    let fileTransfer    = FileTransferEngine.shared
    let hotspot         = HotspotController.shared
    let wifi            = WifiConnectionManager.shared
    let notifBridge     = NotificationBridge.shared
    let callBridge      = CallBridge.shared

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()

        // Start background services
        discovery.startBrowsing()
        clipboard.start()
        notifBridge.startADBPolling()
        callBridge.startCallMonitoring()

        // Pre-fetch app list for app streaming
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.mirroring.fetchInstalledApps()
        }

        print("[AppDelegate] Continuity Suite launched — Motorola Edge 50 Pro")
    }

    func applicationWillTerminate(_ notification: Notification) {
        mirroring.terminateMirroringSession()
        crossControl.releaseControl()
        clipboard.stop()
        notifBridge.stopADBPolling()
        callBridge.stopCallMonitoring()
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "iphone.and.arrow.forward",
                                   accessibilityDescription: "Continuity")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popoverView = PopoverView()
            .environmentObject(mirroring)
            .environmentObject(crossControl)
            .environmentObject(clipboard)
            .environmentObject(fileTransfer)
            .environmentObject(hotspot)
            .environmentObject(discovery)
            .environmentObject(wifi)
            .environmentObject(notifBridge)
            .environmentObject(callBridge)

        let pop = NSPopover()
        pop.contentSize = NSSize(width: 320, height: 520)
        pop.behavior = .semitransient   // stays open during drag operations
        pop.animates = true
        pop.contentViewController = NSHostingController(rootView: popoverView)
        self.popover = pop
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if let pop = popover {
            if pop.isShown {
                pop.performClose(nil)
            } else {
                pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                pop.contentViewController?.view.window?.makeKey()
            }
        }
    }
}
