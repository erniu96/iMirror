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
        window.title = "欢迎使用 iMirror"
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
                Text("欢迎使用 iMirror")
                    .font(.title.bold())
                Text("把 iPhone、iPad 或另一台 Mac 的屏幕投到这台 Mac 上")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 34)
            .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 16) {
                step(1, title: "iMirror 在右上角的菜单栏里") {
                    HStack(spacing: 6) {
                        Text("找到这个图标")
                        Image(nsImage: MenuBarIcon.image)
                            .renderingMode(.template)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                        Text("，点它可以查看状态和设置。")
                    }
                    Text("iMirror 没有 Dock 图标，这是正常的。")
                }
                step(2, title: "在 iPhone 或 iPad 上打开“屏幕镜像”") {
                    Text("从屏幕右上角向下轻扫打开控制中心，轻点“屏幕镜像”按钮。在 Mac 上则点菜单栏的控制中心。")
                }
                step(3, title: "选择“\(model.configuration.advertisedName)”") {
                    Text("设备和这台 Mac 需要连接同一个 Wi-Fi。如果 Mac 询问是否允许 iMirror 访问本地网络，请点“允许”。")
                }
                step(4, title: "第一次连接时输入验证码") {
                    Text("Mac 上会弹出四位数字，在设备上输入即可。之后同一台设备再连接就不需要验证码了。")
                }
                step(5, title: "调整投屏窗口") {
                    Text("把鼠标移到画面上，左上角会出现停止投屏、置顶和全屏按钮。手机的声音会从 Mac 播放。")
                }
            }
            .padding(.horizontal, 36)

            Spacer(minLength: 18)

            VStack(spacing: 12) {
                Toggle(
                    "登录时自动启动 iMirror",
                    isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin)
                )
                .toggleStyle(.checkbox)
                Button("开始使用", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                Text("随时可以在菜单栏的 iMirror 菜单中点“使用帮助”再次查看。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 26)
        }
        .frame(width: 520, height: 700)
    }

    private func step<Content: View>(
        _ number: Int,
        title: String,
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
