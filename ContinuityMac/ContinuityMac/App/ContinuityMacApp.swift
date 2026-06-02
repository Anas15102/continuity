import SwiftUI

@main
struct ContinuityMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — this is a menu bar only app.
        // Windows are opened programmatically by AppDelegate.
        Settings {
            EmptyView()
        }
    }
}
