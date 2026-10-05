import AppKit
import SwiftUI

/// Getting-started guide shown on first launch and whenever the app is opened
/// again while it is already running in the menu bar.
@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private let onDismiss: () -> Void

    init(model: AppModel, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Welcome to iMirror")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: WelcomeView { [weak self] in self?.close() }
                .environmentObject(model)
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let window else { return }
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onDismiss()
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                Text("Welcome to iMirror")
                    .font(.title.bold())
                Text("Mirror an iPhone, iPad or another Mac to this Mac")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 34)
            .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 16) {
                step(1, title: "iMirror lives in the menu bar") {
                    HStack(spacing: 6) {
                        Text("Look for this icon")
                        Image(nsImage: MenuBarIcon.image)
                            .renderingMode(.template)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                        Text("and click it for status and settings.")
                    }
                    Text("iMirror has no Dock icon; that’s expected.")
                }
                step(2, title: "Open Screen Mirroring on your iPhone or iPad") {
                    Text("Swipe down from the top-right corner to open Control Center, then tap Screen Mirroring. On a Mac, use Control Center in the menu bar.")
                }
                step(3, title: "Choose “\(model.configuration.advertisedName)”") {
                    Text("The device and this Mac must be on the same Wi-Fi network. If macOS asks whether iMirror may access the local network, click Allow.")
                }
                step(4, title: "Enter the code the first time") {
                    Text("A four-digit code appears on this Mac; enter it on the device. The same device won’t need a code again.")
                }
                step(5, title: "Use the mirroring window") {
                    Text("Move the pointer over the picture to show the stop, pin and full-screen buttons in the top-left corner. Sound from the device plays on this Mac.")
                }
            }
            .padding(.horizontal, 36)

            Spacer(minLength: 18)

            VStack(spacing: 12) {
                Toggle(
                    "Open iMirror at Login",
                    isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin)
                )
                .toggleStyle(.checkbox)
                Button("Get Started", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                Text("You can show this guide again any time with Help in the iMirror menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 26)
        }
        .frame(width: 520, height: 700)
    }

    private func step<Content: View>(
        _ number: Int,
        title: LocalizedStringKey,
        @ViewBuilder detail: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.callout.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                detail()
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
