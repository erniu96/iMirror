import Foundation

struct ReceiverConfiguration: Equatable {
    static let defaultBaseName = "iMirror"

    let baseName: String
    let installationTag: String

    init(baseName: String, installationTag: String) throws {
        let normalizedName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw ValidationError.invalidName
        }
        let allowedTagCharacters = CharacterSet(charactersIn: "23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        guard installationTag.count == 4,
              installationTag.unicodeScalars.allSatisfy(allowedTagCharacters.contains) else {
            throw ValidationError.invalidInstallationTag
        }
        guard "\(normalizedName)-\(installationTag)".utf8.count <= 63 else {
            throw ValidationError.invalidName
        }

        self.baseName = normalizedName
        self.installationTag = installationTag
    }

    var advertisedName: String {
        "\(baseName)-\(installationTag)"
    }

    enum ValidationError: LocalizedError {
        case invalidName
        case invalidInstallationTag

        var errorDescription: String? {
            switch self {
            case .invalidName:
                return "接收器名称不能为空，且附加设备标记后最多 63 个 UTF-8 字节。"
            case .invalidInstallationTag:
                return "本机投屏标记无效。"
            }
        }
    }
}
