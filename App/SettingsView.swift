import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var receiverName = ""
    @State private var confirmForgetDevices = false
    @State private var confirmResetIdentity = false

    var body: some View {
        TabView {
            Form {
                Section("AirPlay 接收器") {
                    TextField("接收器名称", text: $receiverName)
                    LabeledContent("屏幕镜像中显示") {
                        Text(previewName)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text("每次新设备发起配对时生成新的四位验证码，不会保存固定验证码。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("应用并重启接收器") {
                        model.applyReceiverName(receiverName)
                    }
                    .disabled(receiverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("窗口") {
                    Toggle("投屏窗口始终置顶", isOn: $model.alwaysOnTop)
                    Text("投屏窗口没有标题栏；把鼠标移入窗口后，会在左上角显示停止投屏、置顶和全屏按钮。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("声音") {
                    Toggle("播放投屏设备的声音", isOn: $model.playsAudio)
                    Text("音量跟随投屏设备；在设备上调节音量即可。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("启动") {
                    Toggle(
                        "登录时自动启动",
                        isOn: Binding(
                            get: { model.launchAtLogin },
                            set: model.setLaunchAtLogin
                        )
                    )
                }
            }
            .padding()
            .tabItem { Label("通用", systemImage: "gearshape") }

            Form {
                Section("已配对设备") {
                    Button("忘记所有设备", role: .destructive) {
                        confirmForgetDevices = true
                    }
                    Text("已验证设备下次连接时可跳过验证码。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("接收器身份") {
                    Button("重置接收器身份", role: .destructive) {
                        confirmResetIdentity = true
                    }
                    Text("重置后，所有设备都需要重新验证。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .tabItem { Label("配对", systemImage: "key.fill") }

            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                Text("iMirror")
                    .font(.title.bold())
                Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .foregroundStyle(.secondary)
                Text("macOS 原生菜单栏 AirPlay 屏幕镜像接收器")
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 440)
        .onAppear {
            receiverName = model.configuration.baseName
        }
        .confirmationDialog("忘记所有已配对设备？", isPresented: $confirmForgetDevices) {
            Button("忘记所有设备", role: .destructive) { model.forgetTrustedDevices() }
        }
        .confirmationDialog("重置接收器身份？", isPresented: $confirmResetIdentity) {
            Button("重置并重启", role: .destructive) { model.resetReceiverIdentity() }
        }
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

    private var previewName: String {
        let baseName = receiverName.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(baseName.isEmpty ? ReceiverConfiguration.defaultBaseName : baseName)-\(model.configuration.installationTag)"
    }
}
