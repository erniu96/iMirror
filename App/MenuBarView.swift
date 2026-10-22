import AppKit
import SwiftUI

/// Contents of the menu bar extra, shown as a standard menu (HIG, The menu bar:
/// "Display a menu — not a popover — when people click your menu bar extra").
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openSettings) private var openSettingsAction

    var body: some View {
        Text(model.status.title)
        Text("Receiver Name: \(model.configuration.advertisedName)")

        switch model.status {
        case .streaming(let sessions):
            Divider()
            ForEach(sessions) { session in
                Menu(session.device.name) {
                    Button("Show Window") { model.showMirrorWindow(sessionID: session.id) }
                    Button("Enter or Exit Full Screen") { model.toggleFullScreen(sessionID: session.id) }
                    Divider()
                    Button("Stop Mirroring") { model.stopMirroring(sessionID: session.id) }
                }
            }
            if sessions.count > 1 {
                Button("Show All Windows") { model.showAllMirrorWindows() }
            }
        case .pairing(let code):
            Divider()
            Button("Show Pairing Code (\(code))") { model.showPairingCode() }
        case .failed(let message):
            Text(message)
            Button("Restart Receiver") { model.startReceiver() }
        case .ready, .starting, .stopped:
            Text("In Screen Mirroring, choose “\(model.configuration.advertisedName)”")
        }

        Divider()

        Toggle("Keep Mirroring Windows on Top", isOn: $model.alwaysOnTop)
        Toggle("Play Sound from Mirrored Devices", isOn: $model.playsAudio)

        Divider()

        Button("About iMirror") { model.showAbout() }
        Button("Getting Started Guide") { model.showWelcome() }
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettingsAction()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit iMirror") { model.quit() }
            .keyboardShortcut("q")
    }
}
