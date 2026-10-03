import Foundation

final class PairingStore {
    private let fileManager: FileManager
    private let paths: AppPaths

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.paths = try AppPaths(fileManager: fileManager)
    }

    func forgetTrustedDevices() throws {
        if fileManager.fileExists(atPath: paths.trustedClients.path) {
            try fileManager.removeItem(at: paths.trustedClients)
        }
    }

    func resetReceiverIdentity() throws {
        try forgetTrustedDevices()
        if fileManager.fileExists(atPath: paths.receiverIdentity.path) {
            try fileManager.removeItem(at: paths.receiverIdentity)
        }
    }
}
