import SwiftUI

@main
struct iMirrorApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra(
            "iMirror",
            systemImage: "airplayvideo"
        ) {
            MenuBarView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
