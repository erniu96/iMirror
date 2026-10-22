import AppKit
import SwiftUI

/// Renders the shipping menu, settings, welcome and code windows to PNG files.
/// Windows are kept fully transparent, so nothing visibly appears on screen.
/// Usage: iMirrorScreenshots.app/Contents/MacOS/iMirrorScreenshots <output dir> <light|dark>
@main
struct ScreenshotApp: App {
    @NSApplicationDelegateAdaptor(ScreenshotDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(ScreenshotDelegate.settingsModel)
        }
    }
}

@MainActor
final class ScreenshotDelegate: NSObject, NSApplicationDelegate {
    static let settingsModel = AppModel(status: .ready(port: 7000))

    private var keepAlive: [NSWindowController] = []
    private lazy var outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
    private lazy var isDark = CommandLine.arguments.dropFirst(2).first == "dark"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        Task {
            await captureMenu("menu-ready", status: .ready(port: 7000))
            await captureMenu("menu-pairing", status: .pairing(code: "4831"))
            await captureMenu("menu-streaming", status: .streaming([
                MirroringSessionSummary(id: 1, device: MirroringDevice(name: "iPhone", model: "iPhone17,1")),
                MirroringSessionSummary(id: 2, device: MirroringDevice(name: "iPad", model: "iPad14,8")),
            ]))
            await captureWelcome()
            await capturePinPanel()
            await captureSettings()
            NSApp.terminate(nil)
        }
    }

    private func captureMenu(_ name: String, status: ReceiverStatus) async {
        let hosting = NSHostingView(rootView: MenuBarView()
            .environmentObject(AppModel(status: status))
            .background(Color(nsColor: .windowBackgroundColor)))
        hosting.frame.size = hosting.fittingSize
        let panel = NSPanel(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.contentView = hosting
        await capture(panel, name: name, includeFrame: false)
    }

    private func captureWelcome() async {
        let controller = WelcomeWindowController(model: AppModel(status: .ready(port: 7000))) {}
        keepAlive.append(controller)
        guard let window = controller.window else { return }
        await capture(window, name: "welcome", includeFrame: true)
    }

    private func capturePinPanel() async {
        let controller = PinPanelController()
        keepAlive.append(controller)
        controller.window?.alphaValue = 0
        controller.show(code: "4831")
        guard let window = controller.window else { return }
        await capture(window, name: "code", includeFrame: true)
    }

    private func captureSettings() async {
        // The Settings scene owns its window; hide it as soon as it exists.
        NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: nil, queue: .main) { note in
            (note.object as? NSWindow)?.alphaValue = 0
        }
        let opener = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless], backing: .buffered, defer: false)
        opener.contentView = NSHostingView(rootView: SettingsOpener())
        opener.alphaValue = 0
        opener.orderFront(nil)
        for _ in 0..<20 where settingsWindow == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let window = settingsWindow else {
            FileHandle.standardError.write(Data("Settings window did not open\n".utf8))
            return
        }
        await capture(window, name: "settings", includeFrame: true)
    }

    private var settingsWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true }
    }

    private func capture(_ window: NSWindow, name: String, includeFrame: Bool) async {
        window.alphaValue = 0
        window.appearance = NSApp.appearance
        window.orderFront(nil)
        // Let SwiftUI finish layout and async image loading before drawing.
        try? await Task.sleep(for: .milliseconds(800))

        guard let content = window.contentView else { return }
        let view = includeFrame ? content.superview ?? content : content
        let size = view.bounds.size
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        window.orderOut(nil)

        let url = outputDirectory.appendingPathComponent("\(name).png")
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: url)
            print(url.path)
        } catch {
            FileHandle.standardError.write(Data("\(name): \(error.localizedDescription)\n".utf8))
        }
    }
}

/// The Settings scene can only be opened from SwiftUI on current macOS versions.
private struct SettingsOpener: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear.onAppear { openSettings() }
    }
}
