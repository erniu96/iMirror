import Foundation

struct MirroringDevice: Equatable {
    let name: String
    let model: String
}

struct MirroringSessionSummary: Equatable, Identifiable {
    let id: UInt64
    let device: MirroringDevice
}

enum ReceiverStatus: Equatable {
    case stopped
    case starting
    case ready(port: UInt16)
    case pairing(code: String)
    case streaming([MirroringSessionSummary])
    case failed(message: String)

    var title: String {
        switch self {
        case .stopped:
            return String(localized: "Receiver stopped")
        case .starting:
            return String(localized: "Starting receiver…")
        case .ready:
            return String(localized: "Waiting for a device")
        case .pairing:
            return String(localized: "Waiting for the code")
        case .streaming(let sessions):
            return sessions.count == 1
                ? String(localized: "Receiving mirroring")
                : String(localized: "Receiving from \(sessions.count) devices")
        case .failed:
            return String(localized: "Receiver failed to start")
        }
    }
}
