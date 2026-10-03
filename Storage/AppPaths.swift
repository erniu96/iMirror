import Foundation

struct AppPaths {
    let applicationSupport: URL
    let receiverIdentity: URL
    let trustedClients: URL

    init(fileManager: FileManager = .default) throws {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        applicationSupport = base.appendingPathComponent("iMirror", isDirectory: true)
        receiverIdentity = applicationSupport.appendingPathComponent("airplay-key.pem")
        trustedClients = applicationSupport.appendingPathComponent("trusted-airplay-clients.txt")

        try fileManager.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
