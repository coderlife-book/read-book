import Foundation

struct ImportDropHandler {
    static func firstTXTURL(in urls: [URL]) -> URL? {
        urls.first { $0.isFileURL && $0.pathExtension.lowercased() == "txt" }
    }
}
