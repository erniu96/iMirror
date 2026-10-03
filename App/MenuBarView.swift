import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openSettings) private var openSettingsAction

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader

            if case .streaming(let sessions) = model.status {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(sessions) { session in
                            deviceCard(session)
                        }
                    }
                }
                .frame(maxHeight: 290)

                if sessions.count > 1 {
                    Button("显示全部窗口") { model.showAllMirrorWindows() }
                }
            } else {
                connectionHint
            }

            Divider()

            Toggle("投屏窗口始终置顶", isOn: $model.alwaysOnTop)

            Toggle(
                "登录时自动启动",
                isOn: Binding(
                    get: { model.launchAtLogin },
                    set: model.setLaunchAtLogin
                )
            )

            Divider()

            HStack {
                Button("设置…") {
                    openSettingsAction()
                    NSApp.activate(ignoringOtherApps: true)
                }
                    .keyboardShortcut(",")
                Spacer()
                Button("退出") { model.quit() }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 330)
        .alert(
            "iMirror",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.status.title)
                    .font(.headline)
                Text(model.configuration.advertisedName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func deviceCard(_ session: MirroringSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: deviceSymbol(for: session.device))
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.device.name).fontWeight(.medium)
                    if !session.device.model.isEmpty {
                        Text(session.device.model)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            HStack {
                Button("显示窗口") { model.showMirrorWindow(sessionID: session.id) }
                Button("全屏") { model.toggleFullScreen(sessionID: session.id) }
                Spacer()
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
    }

    private func deviceSymbol(for device: MirroringDevice) -> String {
        let model = device.model.lowercased()
        if model.contains("ipad") { return "ipad" }
        if model.contains("iphone") { return "iphone" }
        if model.contains("mac") { return "laptopcomputer" }
        return "display"
    }

    private var connectionHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .pairing(let code) = model.status {
                Text(code)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                Text("请在发起投屏的 Apple 设备上输入此验证码。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if case .failed(let message) = model.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("重新启动") { model.startReceiver() }
            } else {
                Text("在 iPhone、iPad 或 Mac 的“屏幕镜像”中选择“\(model.configuration.advertisedName)”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .streaming: return .green
        case .pairing: return .orange
        case .ready: return .blue
        case .failed: return .red
        case .starting: return .yellow
        case .stopped: return .secondary
        }
    }

    private var statusSymbol: String {
        switch model.status {
        case .streaming: return "airplayvideo"
        case .pairing: return "lock.fill"
        case .ready: return "antenna.radiowaves.left.and.right"
        case .failed: return "exclamationmark.triangle.fill"
        case .starting: return "ellipsis"
        case .stopped: return "pause.fill"
        }
    }
}
