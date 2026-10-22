import AppKit
import Combine

/// Stand-in for the real AppModel so the shipping views can be rendered with
/// fixed sample data, without starting the AirPlay receiver.
@MainActor
final class AppModel: ObservableObject {
    @Published var status: ReceiverStatus
    @Published var configuration: ReceiverConfiguration
    @Published var launchAtLogin = true
    @Published var alwaysOnTop = true
    @Published var playsAudio = true
    @Published var alertMessage: String?

    init(status: ReceiverStatus) {
        self.status = status
        self.configuration = try! ReceiverConfiguration(baseName: "iMirror", installationTag: "A7K2")
    }

    func showWelcome() {}
    func startReceiver() {}
    func showMirrorWindow(sessionID: UInt64) {}
    func showAllMirrorWindows() {}
    func toggleFullScreen(sessionID: UInt64) {}
    func applyReceiverName(_ name: String) {}
    func setLaunchAtLogin(_ enabled: Bool) { launchAtLogin = enabled }
    func forgetTrustedDevices() {}
    func resetReceiverIdentity() {}
    func quit() { NSApp.terminate(nil) }
}
