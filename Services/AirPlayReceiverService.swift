import Foundation

final class AirPlayReceiverService: NSObject {
    enum Event {
        case started(port: UInt16)
        case stopped
        case pairing(code: String)
        case connected(sessionID: UInt64, device: MirroringDevice)
        case disconnected(sessionID: UInt64)
        case failed(message: String)
    }

    var onEvent: ((Event) -> Void)?

    private let lifecycleQueue = DispatchQueue(label: "com.erniu.imirror.receiver-lifecycle", qos: .userInitiated)
    private let sinkLock = NSLock()
    private let stateLock = NSLock()
    private var videoSink: ((UInt64, Data) -> Void)?
    private var audioSink: AudioPlaybackEngine?
    private var acceptsConnectionEvents = false
    private let bridge: AirPlayReceiverBridge

    override init() {
        bridge = AirPlayReceiverBridge(
            receiverName: ReceiverConfiguration.defaultBaseName,
            pin: 0
        )
        super.init()
        bridge.delegate = self
    }

    func setVideoSink(_ sink: @escaping (UInt64, Data) -> Void) {
        sinkLock.lock()
        videoSink = sink
        sinkLock.unlock()
    }

    func setAudioSink(_ sink: AudioPlaybackEngine) {
        sinkLock.lock()
        audioSink = sink
        sinkLock.unlock()
    }

    private func currentAudioSink() -> AudioPlaybackEngine? {
        guard shouldAcceptConnectionEvent() else { return nil }
        sinkLock.lock()
        let sink = audioSink
        sinkLock.unlock()
        return sink
    }

    func start(configuration: ReceiverConfiguration) {
        lifecycleQueue.async { [weak self] in
            guard let self else { return }
            if self.bridge.isRunning() { return }

            self.bridge.receiverName = configuration.advertisedName
            self.bridge.pin = 0
            self.bridge.isPinFixed = false
            self.setAcceptsConnectionEvents(true)

            do {
                try self.bridge.start()
            } catch {
                self.setAcceptsConnectionEvents(false)
                self.emit(.failed(message: error.localizedDescription))
            }
        }
    }

    func stop() {
        lifecycleQueue.async { [weak self] in
            guard let self else { return }
            self.setAcceptsConnectionEvents(false)
            self.bridge.stop()
        }
    }

    func disconnect(sessionID: UInt64) {
        lifecycleQueue.async { [weak self] in
            self?.bridge.disconnect(sessionID: sessionID)
        }
    }

    func stopSynchronously() {
        lifecycleQueue.sync {
            setAcceptsConnectionEvents(false)
            bridge.stop()
        }
    }

    func restart(configuration: ReceiverConfiguration) {
        lifecycleQueue.async { [weak self] in
            guard let self else { return }
            self.setAcceptsConnectionEvents(false)
            self.bridge.stop()
            self.bridge.receiverName = configuration.advertisedName
            self.bridge.pin = 0
            self.bridge.isPinFixed = false
            self.setAcceptsConnectionEvents(true)

            do {
                try self.bridge.start()
            } catch {
                self.setAcceptsConnectionEvents(false)
                self.emit(.failed(message: error.localizedDescription))
            }
        }
    }

    private func emit(_ event: Event) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }

    private func setAcceptsConnectionEvents(_ value: Bool) {
        stateLock.lock()
        acceptsConnectionEvents = value
        stateLock.unlock()
    }

    private func shouldAcceptConnectionEvent() -> Bool {
        stateLock.lock()
        let value = acceptsConnectionEvents
        stateLock.unlock()
        return value
    }
}

extension AirPlayReceiverService: AirPlayReceiverBridgeDelegate {
    func receiverDidStart(onPort port: UInt16) {
        emit(.started(port: port))
    }

    func receiverDidStop() {
        emit(.stopped)
    }

    func receiverDidRequestPIN(_ pin: String) {
        guard shouldAcceptConnectionEvent() else { return }
        emit(.pairing(code: pin))
    }

    func receiverDidConnect(sessionID: UInt64, name: String, model: String) {
        guard shouldAcceptConnectionEvent() else { return }
        emit(.connected(sessionID: sessionID, device: MirroringDevice(name: name, model: model)))
    }

    func receiverDidReceiveVideoData(_ data: Data, sessionID: UInt64) {
        guard shouldAcceptConnectionEvent() else { return }
        sinkLock.lock()
        let sink = videoSink
        sinkLock.unlock()
        sink?(sessionID, data)
    }

    func receiverDidSetAudioFormat(compressionType: UInt8, sampleRate: UInt32, framesPerPacket: UInt16, sessionID: UInt64) {
        guard let format = AirPlayAudioFormat(
            compressionType: compressionType,
            sampleRate: sampleRate,
            framesPerPacket: UInt32(framesPerPacket)
        ) else {
            NSLog("[AirPlay] Unsupported audio compression type %u", compressionType)
            return
        }
        currentAudioSink()?.configure(sessionID: sessionID, format: format)
    }

    func receiverDidReceiveAudioData(_ data: Data, sessionID: UInt64) {
        currentAudioSink()?.enqueue(sessionID: sessionID, packet: data)
    }

    func receiverDidSetAudioVolume(_ decibels: Float, sessionID: UInt64) {
        currentAudioSink()?.setVolume(sessionID: sessionID, decibels: decibels)
    }

    func receiverDidFlushAudio(sessionID: UInt64) {
        currentAudioSink()?.flush(sessionID: sessionID)
    }

    func receiverDidStopAudio(sessionID: UInt64) {
        currentAudioSink()?.endSession(sessionID: sessionID)
    }

    func receiverDidDisconnect(sessionID: UInt64) {
        guard shouldAcceptConnectionEvent() else { return }
        emit(.disconnected(sessionID: sessionID))
    }
}
