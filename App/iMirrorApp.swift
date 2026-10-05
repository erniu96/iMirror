import AppKit
import SwiftUI

@main
struct iMirrorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

extension Notification.Name {
    static let iMirrorReopenRequested = Notification.Name("com.erniu.imirror.reopen")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// iMirror has no Dock icon or window, so opening it again from Finder or
    /// Launchpad would otherwise look like nothing happened.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .iMirrorReopenRequested, object: nil)
        return false
    }
}
