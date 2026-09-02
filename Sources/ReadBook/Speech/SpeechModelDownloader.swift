import Foundation

struct SpeechDownloadProgress: Equatable, Sendable {
    let downloadedBytes: Int64
    let totalBytes: Int64
}

struct SpeechModelDownloadSource: Equatable, Sendable {
    let baseURL: URL

    static let huggingFace = SpeechModelDownloadSource(
        baseURL: URL(string: "https://huggingface.co")!
    )

    func resolveURL(
        descriptor: SpeechModelDescriptor,
        relativePath: String
    ) throws -> URL {
        guard let scheme = baseURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              baseURL.host != nil else {
            throw SpeechModelDownloadError.invalidSourceURL
        }

        var url = baseURL
        for component in descriptor.repoID.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        url.appendPathComponent("resolve")
        url.appendPathComponent(descriptor.revision)
        for component in relativePath.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        return url
    }
}

enum SpeechModelDownloadSourceMode: String, CaseIterable, Sendable {
    case huggingFace
    case customMirror
}

enum SpeechModelDownloadPreferences {
    static let modeKey = "speechModelDownloadSourceMode"
    static let customMirrorURLKey = "speechModelCustomMirrorURL"

    static func configuredSource(defaults: UserDefaults = .standard) -> SpeechModelDownloadSource {
        let mode = SpeechModelDownloadSourceMode(
            rawValue: defaults.string(forKey: modeKey) ?? ""
        ) ?? .huggingFace
        guard mode == .customMirror else { return .huggingFace }

        let value = (defaults.string(forKey: customMirrorURLKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return SpeechModelDownloadSource(baseURL: URL(string: "invalid://invalid")!)
        }
        return SpeechModelDownloadSource(baseURL: url)
    }
}

protocol SpeechDownloadTransport: Sendable {
    func contentLength(for url: URL) async throws -> Int64
    func bytes(
        for url: URL,
        startingAt offset: Int64
    ) async throws -> AsyncThrowingStream<Data, Error>
}

protocol SpeechModelDownloading: Sendable {
    func download(
        _ descriptor: SpeechModelDescriptor,
        to modelsRoot: URL,
        progress: @Sendable (SpeechDownloadProgress) -> Void
    ) async throws -> URL
}

protocol SpeechModelSourceDownloading: SpeechModelDownloading {
    func download(
        _ descriptor: SpeechModelDescriptor,
        source: SpeechModelDownloadSource,
        to modelsRoot: URL,
        progress: @Sendable (SpeechDownloadProgress) -> Void
    ) async throws -> URL
}

extension SpeechModelSourceDownloading {
    func download(
        _ descriptor: SpeechModelDescriptor,
        to modelsRoot: URL,
        progress: @Sendable (SpeechDownloadProgress) -> Void
    ) async throws -> URL {
        try await download(
            descriptor,
            source: .huggingFace,
            to: modelsRoot,
            progress: progress
        )
    }
}

enum SpeechModelDownloadError: Error, Equatable {
    case invalidSourceURL
    case invalidResponse
    case httpStatus(Int)
    case rangeUnsupported
    case invalidContentLength(String)
    case incompleteFile(String)
    case insufficientDiskSpace(requiredBytes: Int64)
}

struct URLSessionSpeechDownloadTransport: SpeechDownloadTransport {
    func contentLength(for url: URL) async throws -> Int64 {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpeechModelDownloadError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SpeechModelDownloadError.httpStatus(http.statusCode)
        }
        guard response.expectedContentLength >= 0 else {
            throw SpeechModelDownloadError.invalidContentLength(url.lastPathComponent)
        }
        return response.expectedContentLength
    }

    func bytes(
        for url: URL,
        startingAt offset: Int64
    ) async throws -> AsyncThrowingStream<Data, Error> {
        var request = URLRequest(url: url)
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpeechModelDownloadError.invalidResponse
        }
        if offset > 0, http.statusCode == 200 {
            throw SpeechModelDownloadError.rangeUnsupported
        }
        let expectedStatus = offset > 0 ? 206 : 200
        guard http.statusCode == expectedStatus else {
            throw SpeechModelDownloadError.httpStatus(http.statusCode)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var buffer = Data()
                    buffer.reserveCapacity(1_048_576)
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        buffer.append(byte)
                        if buffer.count >= 1_048_576 {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty { continuation.yield(buffer) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

actor SpeechModelDownloader: SpeechModelSourceDownloading {
    private let transport: any SpeechDownloadTransport
    private let fileManager = FileManager.default

    init(transport: any SpeechDownloadTransport = URLSessionSpeechDownloadTransport()) {
        self.transport = transport
    }

    func download(
        _ descriptor: SpeechModelDescriptor,
        source: SpeechModelDownloadSource,
        to modelsRoot: URL,
        progress: @Sendable (SpeechDownloadProgress) -> Void
    ) async throws -> URL {
        let destination = modelsRoot
            .appendingPathComponent(descriptor.kind.rawValue, isDirectory: true)
            .appendingPathComponent(descriptor.revision, isDirectory: true)
        if fileManager.fileExists(atPath: destination.path) { return destination }

        let partialRoot = modelsRoot
            .appendingPathComponent(".partial", isDirectory: true)
            .appendingPathComponent(descriptor.kind.rawValue, isDirectory: true)
            .appendingPathComponent(descriptor.revision, isDirectory: true)
        try fileManager.createDirectory(at: partialRoot, withIntermediateDirectories: true)

        var files: [(path: String, url: URL, total: Int64, existing: Int64)] = []
        for path in descriptor.requiredRelativePaths {
            let remoteURL = try source.resolveURL(descriptor: descriptor, relativePath: path)
            let total = try await transport.contentLength(for: remoteURL)
            guard total >= 0 else { throw SpeechModelDownloadError.invalidContentLength(path) }
            let partialFile = partialRoot.appendingPathComponent(path)
            let existing = fileSize(at: partialFile)
            files.append((path, remoteURL, total, min(existing, total)))
        }

        let totalBytes = files.reduce(Int64(0)) { $0 + $1.total }
        var downloadedBytes = files.reduce(Int64(0)) { $0 + $1.existing }
        let missingBytes = totalBytes - downloadedBytes
        try verifyDiskCapacity(for: missingBytes, at: modelsRoot)
        progress(SpeechDownloadProgress(downloadedBytes: downloadedBytes, totalBytes: totalBytes))

        for file in files {
            try Task.checkCancellation()
            let partialFile = partialRoot.appendingPathComponent(file.path)
            try fileManager.createDirectory(
                at: partialFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if file.existing == file.total { continue }
            if fileSize(at: partialFile) > file.total {
                try Data().write(to: partialFile)
            } else if !fileManager.fileExists(atPath: partialFile.path) {
                try Data().write(to: partialFile)
            }

            let handle = try FileHandle(forWritingTo: partialFile)
            try handle.seekToEnd()
            do {
                let stream = try await transport.bytes(for: file.url, startingAt: file.existing)
                for try await chunk in stream {
                    try Task.checkCancellation()
                    try handle.write(contentsOf: chunk)
                    downloadedBytes += Int64(chunk.count)
                    progress(SpeechDownloadProgress(
                        downloadedBytes: downloadedBytes,
                        totalBytes: totalBytes
                    ))
                }
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }

            guard fileSize(at: partialFile) == file.total else {
                throw SpeechModelDownloadError.incompleteFile(file.path)
            }
        }

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: partialRoot, to: destination)
        return destination
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }

    private func verifyDiskCapacity(for missingBytes: Int64, at url: URL) throws {
        guard missingBytes > 0 else { return }
        let parent = fileManager.fileExists(atPath: url.path) ? url : url.deletingLastPathComponent()
        let values = try? parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values?.volumeAvailableCapacityForImportantUsage else { return }
        let required = Int64((Double(missingBytes) * 1.15).rounded(.up))
        guard available >= required else {
            throw SpeechModelDownloadError.insufficientDiskSpace(requiredBytes: required)
        }
    }
}
