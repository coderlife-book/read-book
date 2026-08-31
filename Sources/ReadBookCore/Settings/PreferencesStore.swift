import Foundation

public struct PreferencesStore {
    private let defaults: UserDefaults
    private let key = "readerPreferences.v1"
    private let safetyPresenceMigrationKey = "readerSafetyPresenceMigration.v016"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() throws -> ReaderPreferences {
        var value: ReaderPreferences
        if let data = defaults.data(forKey: key) {
            value = try JSONDecoder().decode(ReaderPreferences.self, from: data)
        } else {
            value = .defaults
        }

        guard !defaults.bool(forKey: safetyPresenceMigrationKey) else {
            return value
        }

        value.appPresenceMode = .normal
        try save(value)
        defaults.set(true, forKey: safetyPresenceMigrationKey)
        return value
    }

    public func save(_ value: ReaderPreferences) throws {
        defaults.set(try JSONEncoder().encode(value), forKey: key)
    }
}
