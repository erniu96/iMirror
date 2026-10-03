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
            return "接收器已停止"
        case .starting:
            return "正在启动接收器…"
        case .ready:
            return "等待设备投屏"
        case .pairing:
            return "等待输入验证码"
        case .streaming(let sessions):
            return sessions.count == 1 ? "正在接收投屏" : "正在接收 \(sessions.count) 台设备投屏"
        case .failed:
            return "接收器启动失败"
        }
    }
}
