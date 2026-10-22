import SwiftUI

struct SettingsView: View {
    private enum Pane: String {
        case general
        case pairing
    }

    @EnvironmentObject private var model: AppModel
    // HIG, Settings: "Restore the most recently viewed pane."
    @AppStorage("settingsPane") private var pane = Pane.general
    @State private var receiverName = ""
    @State private var confirmForgetDevices = false
    @State private var confirmResetIdentity = false

    var body: some View {
        TabView(selection: $pane) {
            generalPane
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Pane.general)
            pairingPane
                .tabItem { Label("Pairing", systemImage: "key") }
                .tag(Pane.pairing)
        }
        // The width is fixed and the height follows the pane, so longer
        // translations wrap instead of being clipped.
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            receiverName = model.configuration.baseName
        }
    }

    private var generalPane: some View {
        Form {
            Section {
                TextField("Receiver Name:", text: $receiverName)
                    .onSubmit(applyReceiverName)
                LabeledContent("Shown as:") {
                    Text(previewName)
                        .textSelection(.enabled)
                }
                Button("Apply and Restart Receiver", action: applyReceiverName)
                    .disabled(!canApplyReceiverName)
                note("This is the name to choose in Screen Mirroring on your iPhone or iPad. The tag after it tells your Macs apart.")
            }

            Divider()

            Section {
                Toggle("Keep mirroring windows on top", isOn: $model.alwaysOnTop)
                note("Mirroring windows have no title bar. Move the pointer over a window to show the stop, pin and full-screen buttons in its top-left corner.")
            }

            Section {
                Toggle("Play sound from mirrored devices", isOn: $model.playsAudio)
                note("Volume follows the mirroring device; adjust it there.")
            }

            Section {
                Toggle(
                    "Open iMirror at login",
                    isOn: Binding(
                        get: { model.launchAtLogin },
                        set: model.setLaunchAtLogin
                    )
                )
            }
        }
        .padding(20)
    }

    private var pairingPane: some View {
        Form {
            Section {
                note("A new four-digit code is generated each time a new device pairs; no fixed code is stored. Verified devices can reconnect without a code.")
                Button("Forget All Devices…") {
                    confirmForgetDevices = true
                }
            }

            Divider()

            Section {
                Button("Reset Receiver Identity…") {
                    confirmResetIdentity = true
                }
                note("After a reset, every device must verify again.")
            }
        }
        .padding(20)
        .confirmationDialog("Forget all paired devices?", isPresented: $confirmForgetDevices) {
            Button("Forget All Devices") { model.forgetTrustedDevices() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each device will need a new code the next time it mirrors to this Mac.")
        }
        .confirmationDialog("Reset the receiver identity?", isPresented: $confirmResetIdentity) {
            Button("Reset and Restart") { model.resetReceiverIdentity() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The receiver restarts, current mirroring stops and every device must verify again. This can’t be undone.")
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var trimmedName: String {
        receiverName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canApplyReceiverName: Bool {
        !trimmedName.isEmpty && trimmedName != model.configuration.baseName
    }

    private func applyReceiverName() {
        guard canApplyReceiverName else { return }
        model.applyReceiverName(receiverName)
    }

    private var previewName: String {
        "\(trimmedName.isEmpty ? ReceiverConfiguration.defaultBaseName : trimmedName)-\(model.configuration.installationTag)"
    }
}
