import Foundation

public struct PreferencesStore {
    private let defaults: UserDefaults
    private let key = "readerPreferences.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() throws -> ReaderPreferences {
        guard let data = defaults.data(forKey: key) else { return .defaults }
        return try JSONDecoder().decode(ReaderPreferences.self, from: data)
    }

    public func save(_ value: ReaderPreferences) throws {
        defaults.set(try JSONEncoder().encode(value), forKey: key)
    }
}
