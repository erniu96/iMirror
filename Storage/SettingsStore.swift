import Foundation

final class SettingsStore {
    private enum Key {
        static let receiverName = "receiverName"
        static let installationTag = "installationTag"
        static let alwaysOnTop = "alwaysOnTop"
        static let playsAudio = "playsAudio"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadConfiguration() -> ReceiverConfiguration {
        let baseName = defaults.string(forKey: Key.receiverName) ?? ReceiverConfiguration.defaultBaseName
        let installationTag = loadOrCreateInstallationTag()
        return (try? ReceiverConfiguration(baseName: baseName, installationTag: installationTag))
            ?? (try! ReceiverConfiguration(baseName: ReceiverConfiguration.defaultBaseName, installationTag: installationTag))
    }

    func saveBaseName(_ baseName: String) throws -> ReceiverConfiguration {
        let configuration = try ReceiverConfiguration(
            baseName: baseName,
            installationTag: loadOrCreateInstallationTag()
        )
        defaults.set(configuration.baseName, forKey: Key.receiverName)
        return configuration
    }

    var alwaysOnTop: Bool {
        get {
            if defaults.object(forKey: Key.alwaysOnTop) == nil { return true }
            return defaults.bool(forKey: Key.alwaysOnTop)
        }
        set { defaults.set(newValue, forKey: Key.alwaysOnTop) }
    }

    var playsAudio: Bool {
        get {
            if defaults.object(forKey: Key.playsAudio) == nil { return true }
            return defaults.bool(forKey: Key.playsAudio)
        }
        set { defaults.set(newValue, forKey: Key.playsAudio) }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    private func loadOrCreateInstallationTag() -> String {
        if let stored = defaults.string(forKey: Key.installationTag),
           let configuration = try? ReceiverConfiguration(
               baseName: ReceiverConfiguration.defaultBaseName,
               installationTag: stored
           ) {
            return configuration.installationTag
        }

        let alphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        var generator = SystemRandomNumberGenerator()
        let tag = String((0..<4).map { _ in alphabet.randomElement(using: &generator)! })
        defaults.set(tag, forKey: Key.installationTag)
        return tag
    }
}
