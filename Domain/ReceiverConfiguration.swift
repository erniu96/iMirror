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
                return String(localized: "The receiver name can’t be empty and, with the device tag added, must fit in 63 UTF-8 bytes.")
            case .invalidInstallationTag:
                return String(localized: "The device tag is invalid.")
            }
        }
    }
}
