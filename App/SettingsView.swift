import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var receiverName = ""
    @State private var confirmForgetDevices = false
    @State private var confirmResetIdentity = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        TabView {
            Form {
                Section("AirPlay Receiver") {
                    TextField("Receiver Name", text: $receiverName)
                    LabeledContent("Shown in Screen Mirroring") {
                        Text(previewName)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text("A new four-digit code is generated each time a new device pairs; no fixed code is stored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Apply and Restart Receiver") {
                        model.applyReceiverName(receiverName)
                    }
                    .disabled(receiverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Windows") {
                    Toggle("Keep Mirroring Windows on Top", isOn: $model.alwaysOnTop)
                    Text("Mirroring windows have no title bar. Move the pointer over a window to show the stop, pin and full-screen buttons in its top-left corner.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Sound") {
                    Toggle("Play Sound from Mirrored Devices", isOn: $model.playsAudio)
                    Text("Volume follows the mirroring device; adjust it there.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Startup") {
                    Toggle(
                        "Open at Login",
                        isOn: Binding(
                            get: { model.launchAtLogin },
                            set: model.setLaunchAtLogin
                        )
                    )
                }
            }
            .padding()
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Paired Devices") {
                    Button("Forget All Devices", role: .destructive) {
                        confirmForgetDevices = true
                    }
                    Text("Verified devices can reconnect without a code.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Receiver Identity") {
                    Button("Reset Receiver Identity", role: .destructive) {
                        confirmResetIdentity = true
                    }
                    Text("After a reset, every device must verify again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .tabItem { Label("Pairing", systemImage: "key.fill") }

            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                Text(verbatim: "iMirror")
                    .font(.title.bold())
                Text("Version \(appVersion)")
                    .foregroundStyle(.secondary)
                Text("A native macOS menu bar AirPlay screen mirroring receiver")
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 440)
        .onAppear {
            receiverName = model.configuration.baseName
        }
        .confirmationDialog("Forget all paired devices?", isPresented: $confirmForgetDevices) {
            Button("Forget All Devices", role: .destructive) { model.forgetTrustedDevices() }
        }
        .confirmationDialog("Reset the receiver identity?", isPresented: $confirmResetIdentity) {
            Button("Reset and Restart", role: .destructive) { model.resetReceiverIdentity() }
        }
        .alert(
            "iMirror",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var previewName: String {
        let baseName = receiverName.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(baseName.isEmpty ? ReceiverConfiguration.defaultBaseName : baseName)-\(model.configuration.installationTag)"
    }
}
