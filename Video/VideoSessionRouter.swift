import Foundation

protocol VideoDataSink: AnyObject {
    func enqueue(_ accessUnit: Data)
}

/// Keeps compressed video from different RAOP connections strictly isolated.
/// A small bounded buffer preserves SPS/PPS and the first key frame while the
/// main actor creates the session's decoder and window.
final class VideoSessionRouter {
    private struct PendingStream {
        var accessUnits: [Data] = []
        var byteCount = 0
    }

    private let lock = NSLock()
    private let maximumPendingBytes: Int
    private var sinks: [UInt64: VideoDataSink] = [:]
    private var pendingStreams: [UInt64: PendingStream] = [:]
    private var closedSessions = Set<UInt64>()

    init(maximumPendingBytes: Int = 8 * 1_024 * 1_024) {
        precondition(maximumPendingBytes > 0)
        self.maximumPendingBytes = maximumPendingBytes
    }

    func route(sessionID: UInt64, accessUnit: Data) {
        lock.lock()
        if closedSessions.contains(sessionID) {
            lock.unlock()
            return
        }
        if let sink = sinks[sessionID] {
            lock.unlock()
            sink.enqueue(accessUnit)
            return
        }

        var stream = pendingStreams[sessionID, default: PendingStream()]
        stream.accessUnits.append(accessUnit)
        stream.byteCount += accessUnit.count
        while stream.byteCount > maximumPendingBytes, !stream.accessUnits.isEmpty {
            stream.byteCount -= stream.accessUnits.removeFirst().count
        }
        pendingStreams[sessionID] = stream
        lock.unlock()
    }

    func attach(sessionID: UInt64, sink: VideoDataSink) {
        lock.lock()
        closedSessions.remove(sessionID)
        var bufferedAccessUnits = pendingStreams.removeValue(forKey: sessionID)?.accessUnits ?? []
        lock.unlock()

        // Keep the sink unpublished until every buffered unit has been queued.
        // Packets arriving during replay remain buffered, preserving wire order.
        while true {
            bufferedAccessUnits.forEach(sink.enqueue)

            lock.lock()
            if let nextBatch = pendingStreams.removeValue(forKey: sessionID)?.accessUnits,
               !nextBatch.isEmpty {
                lock.unlock()
                bufferedAccessUnits = nextBatch
                continue
            }
            sinks[sessionID] = sink
            lock.unlock()
            break
        }
    }

    func detach(sessionID: UInt64) {
        lock.lock()
        sinks.removeValue(forKey: sessionID)
        pendingStreams.removeValue(forKey: sessionID)
        closedSessions.insert(sessionID)
        lock.unlock()
    }

    func detachAll() {
        lock.lock()
        closedSessions.formUnion(sinks.keys)
        closedSessions.formUnion(pendingStreams.keys)
        sinks.removeAll()
        pendingStreams.removeAll()
        lock.unlock()
    }
}
