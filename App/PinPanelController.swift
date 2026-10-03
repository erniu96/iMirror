import AppKit
import SwiftUI

@MainActor
final class PinPanelController: NSWindowController {
    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 180),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "iMirror 验证码"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        super.init(window: panel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(code: String) {
        guard let window else { return }
        window.contentView = NSHostingView(rootView: PinPanelContent(code: code))
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
            Text("在发起投屏的设备上输入")
                .font(.headline)
            Text(code)
                .font(.system(size: 38, weight: .bold, design: .monospaced))
                .textSelection(.enabled)
            Text("验证成功后，此窗口会自动隐藏。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 360, height: 180)
    }
}
