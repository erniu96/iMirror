import AVFoundation
import Foundation

/// Plays the audio of every mirroring session through one shared AVAudioEngine.
/// Each session owns its decoder and player node, so sessions start, stop and
/// change volume independently. All state is confined to `queue`.
final class AudioPlaybackEngine {
    /// Packets beyond this much queued audio are dropped so latency cannot grow
    /// when the sender's clock runs slightly faster than the output device.
    private static let maximumQueuedSeconds = 0.35

    private final class Stream {
        let decoder: AudioPacketDecoder
        let player = AVAudioPlayerNode()
        var queuedFrames: AVAudioFramePosition = 0
        /// Bumped whenever queued buffers are discarded, so their late
        /// completion callbacks do not corrupt `queuedFrames`.
        var generation = 0
        var gain: Float = 1

        func discardQueuedAudio() {
            generation += 1
            queuedFrames = 0
            player.stop()
        }

        init(decoder: AudioPacketDecoder) {
            self.decoder = decoder
        }
    }

    var onError: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "com.erniu.imirror.audio", qos: .userInteractive)
    private var streams: [UInt64: Stream] = [:]
    private var pendingGains: [UInt64: Float] = [:]
    private var configurationObserver: NSObjectProtocol?
    private var isMuted = false
    private var lastStartFailure = Date.distantPast
    private var hasReportedStartFailure = false

    init() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.queue.async { self?.restartAfterConfigurationChange() }
        }
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        engine.stop()
    }

    func setMuted(_ muted: Bool) {
        queue.async { [self] in
            isMuted = muted
            engine.mainMixerNode.outputVolume = muted ? 0 : 1
        }
    }

    /// Called when the sender negotiates or renegotiates the audio stream.
    func configure(sessionID: UInt64, format: AirPlayAudioFormat) {
        queue.async { [self] in
            if let stream = streams[sessionID], stream.decoder.format == format { return }
            removeStream(sessionID: sessionID)
            do {
                let stream = Stream(decoder: try AudioPacketDecoder(format: format))
                stream.gain = pendingGains[sessionID] ?? 1
                engine.attach(stream.player)
                engine.connect(stream.player, to: engine.mainMixerNode, format: stream.decoder.outputFormat)
                stream.player.volume = stream.gain
                streams[sessionID] = stream
                startEngineIfNeeded()
                stream.player.play()
            } catch {
                report(error.localizedDescription)
            }
        }
    }

    func enqueue(sessionID: UInt64, packet: Data) {
        queue.async { [self] in
            guard let stream = streams[sessionID] else { return }
            let limit = AVAudioFramePosition(Double(stream.decoder.format.sampleRate) * Self.maximumQueuedSeconds)
            guard stream.queuedFrames < limit,
                  let buffer = stream.decoder.decode(packet) else { return }
            if !engine.isRunning {
                startEngineIfNeeded()
                guard engine.isRunning else { return }
            }
            if !stream.player.isPlaying { stream.player.play() }

            let frames = AVAudioFramePosition(buffer.frameLength)
            let generation = stream.generation
            stream.queuedFrames += frames
            stream.player.scheduleBuffer(buffer) { [weak self, weak stream] in
                self?.queue.async {
                    guard let stream, stream.generation == generation else { return }
                    stream.queuedFrames -= frames
                }
            }
        }
    }

    /// AirPlay volume is in decibels: 0 is full scale, -30 the quietest audible step, -144 mute.
    func setVolume(sessionID: UInt64, decibels: Float) {
        queue.async { [self] in
            let gain: Float = decibels <= -30 ? 0 : min(1, powf(10, decibels / 20))
            pendingGains[sessionID] = gain
            if let stream = streams[sessionID] {
                stream.gain = gain
                stream.player.volume = gain
            }
        }
    }

    /// Drops queued audio, e.g. when the sender pauses or seeks.
    func flush(sessionID: UInt64) {
        queue.async { [self] in
            guard let stream = streams[sessionID] else { return }
            stream.discardQueuedAudio()
            stream.decoder.reset()
            if engine.isRunning { stream.player.play() }
        }
    }

    func endSession(sessionID: UInt64) {
        queue.async { [self] in
            removeStream(sessionID: sessionID)
            pendingGains.removeValue(forKey: sessionID)
        }
    }

    func endAllSessions() {
        queue.async { [self] in
            Array(streams.keys).forEach { removeStream(sessionID: $0) }
            pendingGains.removeAll()
        }
    }

    private func removeStream(sessionID: UInt64) {
        guard let stream = streams.removeValue(forKey: sessionID) else { return }
        stream.discardQueuedAudio()
        engine.detach(stream.player)
        if streams.isEmpty { engine.stop() }
    }

    private func startEngineIfNeeded() {
        guard !engine.isRunning, !streams.isEmpty else { return }
        // Packets arrive ~90 times a second; do not retry a failing device on every one.
        guard Date().timeIntervalSince(lastStartFailure) > 2 else { return }
        engine.mainMixerNode.outputVolume = isMuted ? 0 : 1
        engine.prepare()
        do {
            try engine.start()
            hasReportedStartFailure = false
        } catch {
            lastStartFailure = Date()
            if !hasReportedStartFailure {
                hasReportedStartFailure = true
                report(String(localized: "Couldn’t start audio output: \(error.localizedDescription)"))
            }
        }
    }

    /// The engine stops itself when the output device or its format changes.
    private func restartAfterConfigurationChange() {
        guard !streams.isEmpty else { return }
        lastStartFailure = .distantPast
        for stream in streams.values {
            stream.discardQueuedAudio()
            engine.connect(stream.player, to: engine.mainMixerNode, format: stream.decoder.outputFormat)
        }
        startEngineIfNeeded()
        if engine.isRunning {
            streams.values.forEach { $0.player.play() }
        }
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onError?(message) }
    }
}
