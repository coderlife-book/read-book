import Foundation

public struct AppPaths: Sendable {
    public let root: URL

    public var booksRoot: URL { root.appendingPathComponent("Books", isDirectory: true) }
    public var cacheRoot: URL { root.appendingPathComponent("Cache", isDirectory: true) }
    public var modelsRoot: URL { root.appendingPathComponent("Models", isDirectory: true) }
    public var modelDownloadsRoot: URL { modelsRoot.appendingPathComponent(".partial", isDirectory: true) }
    public var libraryIndexURL: URL { root.appendingPathComponent("library.json") }

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            self.root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ReadBook", isDirectory: true)
        }
    }

    public func bookDirectory(_ id: UUID) -> URL {
        booksRoot.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func contentURL(_ id: UUID) -> URL {
        bookDirectory(id).appendingPathComponent("content.txt")
    }

    public func metadataURL(_ id: UUID) -> URL {
        bookDirectory(id).appendingPathComponent("metadata.json")
    }
}
