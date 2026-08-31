import Foundation

public struct PageCacheKey: Hashable, Sendable {
    public let bookID: UUID
    public let signature: LayoutSignature
    public let startOffset: Int

    public init(bookID: UUID, signature: LayoutSignature, startOffset: Int) {
        self.bookID = bookID
        self.signature = signature
        self.startOffset = startOffset
    }
}

public final class PageCache: @unchecked Sendable {
    private var pages: [PageCacheKey: PageRange] = [:]
    private let lock = NSLock()

    public init() {}

    public func value(for key: PageCacheKey) -> PageRange? {
        lock.lock()
        defer { lock.unlock() }
        return pages[key]
    }

    public func insert(_ range: PageRange, for key: PageCacheKey) {
        lock.lock()
        defer { lock.unlock() }
        pages[key] = range
    }

    public func invalidate(bookID: UUID? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let bookID {
            pages = pages.filter { $0.key.bookID != bookID }
        } else {
            pages.removeAll(keepingCapacity: true)
        }
    }
}
