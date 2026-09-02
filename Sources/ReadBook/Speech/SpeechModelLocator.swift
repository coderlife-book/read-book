import Foundation

struct SpeechModelLocations: Equatable, Sendable {
    let tts: URL?
    let aligner: URL?

    var isReady: Bool { tts != nil && aligner != nil }
}

struct SpeechModelLocator: Sendable {
    let ownedRoot: URL
    let externalHubRoots: [URL]

    init(
        ownedRoot: URL,
        externalHubRoots: [URL]
    ) {
        self.ownedRoot = ownedRoot
        self.externalHubRoots = externalHubRoots
    }

    func locate(_ descriptor: SpeechModelDescriptor) throws -> URL? {
        let owned = ownedRoot
            .appendingPathComponent(descriptor.kind.rawValue, isDirectory: true)
            .appendingPathComponent(descriptor.revision, isDirectory: true)
        if try validateSnapshot(owned, descriptor: descriptor) {
            return owned
        }

        for hubRoot in externalHubRoots {
            let snapshot = hubRoot
                .appendingPathComponent(descriptor.huggingFaceCacheName, isDirectory: true)
                .appendingPathComponent("snapshots", isDirectory: true)
                .appendingPathComponent(descriptor.revision, isDirectory: true)
            if try validateSnapshot(snapshot, descriptor: descriptor) {
                return snapshot
            }
        }
        return nil
    }

    func locateAll() throws -> SpeechModelLocations {
        SpeechModelLocations(
            tts: try locate(SpeechModelCatalog.tts),
            aligner: try locate(SpeechModelCatalog.aligner)
        )
    }

    func validateSnapshot(
        _ snapshot: URL,
        descriptor: SpeechModelDescriptor
    ) throws -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: snapshot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return false }

        if containsIncompleteFile(in: snapshot) { return false }

        for relativePath in descriptor.requiredRelativePaths {
            let path = snapshot.appendingPathComponent(relativePath).path
            guard fileManager.fileExists(atPath: path) else { return false }
        }

        let indexURL = snapshot.appendingPathComponent("model.safetensors.index.json")
        if fileManager.fileExists(atPath: indexURL.path) {
            let data = try Data(contentsOf: indexURL)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let weightMap = object["weight_map"] as? [String: String] else { return false }
            for shard in Set(weightMap.values) {
                guard fileManager.fileExists(
                    atPath: snapshot.appendingPathComponent(shard).path
                ) else { return false }
            }
        }
        return true
    }

    private func containsIncompleteFile(in root: URL) -> Bool {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return true }

        for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(".incomplete") {
            return true
        }
        return false
    }
}
