import AppKit
import SwiftUI

@MainActor
final class PinPanelController: NSWindowController {
    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        // HIG, Panels: a brief noun title that describes the panel's purpose.
        panel.title = String(localized: "Pairing Code")
        panel.level = .floating
        // Stays visible while iMirror is inactive: people read the code here while
        // typing it on the other device.
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        // HIG, Panels: "avoid making a panel's minimize button available."
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: panel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(code: String) {
        guard let window else { return }
        let hosting = NSHostingView(rootView: PinPanelContent(code: code))
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        window?.orderOut(nil)
    }
}

private struct PinPanelContent: View {
    let code: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Enter this code on the device that is mirroring")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(code)
                .font(.system(size: 38, weight: .bold, design: .monospaced))
                .textSelection(.enabled)
                // Read digit by digit rather than as a number.
                .accessibilityLabel(code.map(String.init).joined(separator: " "))
            Text("This window closes once the device is verified.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
        .frame(width: 360)
    }
}
