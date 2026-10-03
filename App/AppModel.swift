import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var status: ReceiverStatus = .stopped
    @Published private(set) var configuration: ReceiverConfiguration
    @Published private(set) var launchAtLogin: Bool
    @Published var alwaysOnTop: Bool {
        didSet {
            settingsStore.alwaysOnTop = alwaysOnTop
            sessions.values.forEach { $0.windowController.isAlwaysOnTop = alwaysOnTop }
        }
    }
    @Published var alertMessage: String?

    private let receiverService: AirPlayReceiverService
    private let settingsStore: SettingsStore
    private let pairingStore: PairingStore?
    private let loginItemService: LoginItemService
    private let videoRouter: VideoSessionRouter
    private var sessions: [UInt64: MirroringSession] = [:]
    private var sessionOrder: [UInt64] = []
    private var pinPanelController: PinPanelController?
    private var currentPort: UInt16 = 0
    private var cancellables = Set<AnyCancellable>()

    private struct MirroringSession {
        let summary: MirroringSessionSummary
        let windowController: MirrorWindowController
    }

    init() {
        let settingsStore = SettingsStore()
        let configuration = settingsStore.loadConfiguration()
        let receiverService = AirPlayReceiverService()
        let loginItemService = LoginItemService()
        let videoRouter = VideoSessionRouter()

        self.settingsStore = settingsStore
        self.configuration = configuration
        self.receiverService = receiverService
        self.loginItemService = loginItemService
        self.launchAtLogin = loginItemService.isEnabled
        self.alwaysOnTop = settingsStore.alwaysOnTop
        self.videoRouter = videoRouter
        self.pairingStore = try? PairingStore()

        ProcessInfo.processInfo.disableAutomaticTermination("iMirror AirPlay receiver")
        receiverService.setVideoSink { [weak videoRouter] sessionID, data in
            videoRouter?.route(sessionID: sessionID, accessUnit: data)
        }
        receiverService.onEvent = { [weak self] event in
            self?.handle(event)
        }
        observeSystemLifecycle()
        startReceiver()
    }

    func startReceiver() {
        guard status == .stopped || isFailure else { return }
        status = .starting
        receiverService.start(configuration: configuration)
    }

    func stopReceiver() {
        receiverService.stop()
        endAllSessions()
        pinPanelController?.dismiss()
        status = .stopped
    }

    func showMirrorWindow(sessionID: UInt64) {
        guard let session = sessions[sessionID] else { return }
        session.windowController.showWindow(nil)
        session.windowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showAllMirrorWindows() {
        sessionOrder.compactMap { sessions[$0] }.forEach {
            $0.windowController.showWindow(nil)
            $0.windowController.window?.orderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggleFullScreen(sessionID: UInt64) {
        sessions[sessionID]?.windowController.toggleFullScreen()
    }

    func applyReceiverName(_ name: String) {
        do {
            let updated = try settingsStore.saveBaseName(name)
            configuration = updated
            status = .starting
            pinPanelController?.dismiss()
            endAllSessions()
            receiverService.restart(configuration: updated)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItemService.setEnabled(enabled)
            launchAtLogin = loginItemService.isEnabled
        } catch {
            launchAtLogin = loginItemService.isEnabled
            alertMessage = "无法修改开机自启动：\(error.localizedDescription)"
        }
    }

    func forgetTrustedDevices() {
        do {
            try pairingStore?.forgetTrustedDevices()
        } catch {
            alertMessage = "无法清除配对设备：\(error.localizedDescription)"
        }
    }

    func resetReceiverIdentity() {
        do {
            try pairingStore?.resetReceiverIdentity()
            status = .starting
            endAllSessions()
            receiverService.restart(configuration: configuration)
        } catch {
            alertMessage = "无法重置接收器身份：\(error.localizedDescription)"
        }
    }

    func quit() {
        receiverService.stopSynchronously()
        NSApp.terminate(nil)
    }

    private var isFailure: Bool {
        if case .failed = status { return true }
        return false
    }

    private func handle(_ event: AirPlayReceiverService.Event) {
        switch event {
        case .started(let port):
            currentPort = port
            status = .ready(port: port)
        case .stopped:
            currentPort = 0
            endAllSessions()
            if status != .starting { status = .stopped }
        case .pairing(let code):
            if sessions.isEmpty {
                status = .pairing(code: code)
            } else {
                refreshStreamingStatus()
            }
            if pinPanelController == nil {
                pinPanelController = PinPanelController()
            }
            pinPanelController?.show(code: code)
        case .connected(let sessionID, let device):
            beginSession(sessionID: sessionID, device: device)
            pinPanelController?.dismiss()
        case .disconnected(let sessionID):
            endSession(sessionID: sessionID)
        case .failed(let message):
            status = .failed(message: message)
            alertMessage = message
        }
    }

    private func beginSession(sessionID: UInt64, device: MirroringDevice) {
        guard sessions[sessionID] == nil else { return }

        let pipeline = VideoPipeline()
        pipeline.onError = { [weak self] message in
            self?.alertMessage = "\(device.name)：\(message)"
        }

        do {
            let windowController = try MirrorWindowController(
                pipeline: pipeline,
                alwaysOnTop: alwaysOnTop,
                title: device.name,
                onClose: { [weak self] in
                    self?.receiverService.disconnect(sessionID: sessionID)
                }
            )
            let summary = MirroringSessionSummary(id: sessionID, device: device)
            sessions[sessionID] = MirroringSession(
                summary: summary,
                windowController: windowController
            )
            sessionOrder.append(sessionID)
            videoRouter.attach(sessionID: sessionID, sink: pipeline)
            refreshStreamingStatus()
            windowController.beginSession(cascadeIndex: sessionOrder.count - 1)
        } catch {
            videoRouter.detach(sessionID: sessionID)
            alertMessage = "无法为 \(device.name) 创建投屏窗口：\(error.localizedDescription)"
        }
    }

    private func endSession(sessionID: UInt64) {
        videoRouter.detach(sessionID: sessionID)
        sessions.removeValue(forKey: sessionID)?.windowController.endSession()
        sessionOrder.removeAll { $0 == sessionID }
        refreshStreamingStatus()
    }

    private func endAllSessions() {
        videoRouter.detachAll()
        sessions.values.forEach { $0.windowController.endSession() }
        sessions.removeAll()
        sessionOrder.removeAll()
    }

    private func refreshStreamingStatus() {
        let summaries = sessionOrder.compactMap { sessions[$0]?.summary }
        status = summaries.isEmpty ? .ready(port: currentPort) : .streaming(summaries)
    }

    private func observeSystemLifecycle() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.stopReceiver() }
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self?.startReceiver()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.receiverService.stopSynchronously()
            }
            .store(in: &cancellables)
    }
}
