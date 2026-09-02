import Foundation
import Observation

protocol SpeechPlaybackStopping: Sendable {
    func stopForModelDeletion() async
}

enum SpeechModelState: Equatable, Sendable {
    case notInstalled(missingBytes: Int64)
    case discovering
    case downloading(SpeechDownloadProgress)
    case ready(SpeechModelLocations)
    case failed(String)
}

private enum SpeechModelImportError: Error {
    case invalidSnapshot
}

@MainActor
@Observable
final class SpeechModelManager {
    private let locator: SpeechModelLocator
    private let downloader: any SpeechModelDownloading
    private let stopper: any SpeechPlaybackStopping
    private let modelsRoot: URL

    private(set) var state: SpeechModelState = .notInstalled(
        missingBytes: SpeechModelCatalog.all.reduce(0) { $0 + $1.approximateBytes }
    )
    private(set) var installedKinds: Set<SpeechModelKind> = []
    private(set) var downloadingKind: SpeechModelKind?
    private(set) var downloadProgress: SpeechDownloadProgress?

    init(
        locator: SpeechModelLocator,
        downloader: any SpeechModelDownloading,
        stopper: any SpeechPlaybackStopping,
        modelsRoot: URL
    ) {
        self.locator = locator
        self.downloader = downloader
        self.stopper = stopper
        self.modelsRoot = modelsRoot
    }

    func discover() async {
        state = .discovering
        do {
            let locations = try locator.locateAll()
            updateInstalledKinds(locations)
            state = state(for: locations)
        } catch {
            state = .failed("听书模型校验失败：\(error.localizedDescription)")
        }
    }

    func prepareMissingModels(
        source: SpeechModelDownloadSource = .huggingFace
    ) async {
        state = .discovering
        do {
            var locations = try locator.locateAll()
            updateInstalledKinds(locations)
            for descriptor in SpeechModelCatalog.all {
                let isPresent = descriptor.kind == .tts ? locations.tts != nil : locations.aligner != nil
                guard !isPresent else { continue }
                try await download(descriptor, source: source)
                locations = try locator.locateAll()
                updateInstalledKinds(locations)
            }
            state = state(for: locations)
        } catch is CancellationError {
            await discover()
        } catch {
            downloadingKind = nil
            downloadProgress = nil
            state = .failed(downloadFailureMessage(error))
        }
    }

    func prepareModel(
        _ kind: SpeechModelKind,
        source: SpeechModelDownloadSource = .huggingFace
    ) async {
        state = .discovering
        do {
            var locations = try locator.locateAll()
            updateInstalledKinds(locations)
            let isPresent = kind == .tts ? locations.tts != nil : locations.aligner != nil
            if !isPresent {
                try await download(SpeechModelCatalog.descriptor(for: kind), source: source)
                locations = try locator.locateAll()
                updateInstalledKinds(locations)
            }
            state = state(for: locations)
        } catch is CancellationError {
            await discover()
        } catch {
            downloadingKind = nil
            downloadProgress = nil
            state = .failed(downloadFailureMessage(error))
        }
    }

    func importModel(_ kind: SpeechModelKind, from source: URL) async {
        state = .discovering
        let descriptor = SpeechModelCatalog.descriptor(for: kind)
        let destination = modelsRoot
            .appendingPathComponent(kind.rawValue, isDirectory: true)
            .appendingPathComponent(descriptor.revision, isDirectory: true)
        let staging = modelsRoot
            .appendingPathComponent(".importing", isDirectory: true)
            .appendingPathComponent("\(kind.rawValue)-\(UUID().uuidString)", isDirectory: true)

        do {
            guard try locator.validateSnapshot(source, descriptor: descriptor) else {
                throw SpeechModelImportError.invalidSnapshot
            }

            let sourcePath = source.standardizedFileURL.resolvingSymlinksInPath().path
            let destinationPath = destination.standardizedFileURL.resolvingSymlinksInPath().path
            if sourcePath != destinationPath {
                try materializeSnapshot(from: source, to: staging)
                guard try locator.validateSnapshot(staging, descriptor: descriptor) else {
                    throw SpeechModelImportError.invalidSnapshot
                }
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: staging, to: destination)
            }

            try? FileManager.default.removeItem(at: staging.deletingLastPathComponent())
            let locations = try locator.locateAll()
            updateInstalledKinds(locations)
            state = state(for: locations)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            state = .failed(importFailureMessage(error, kind: kind))
        }
    }

    func deleteInstalledModels() async throws {
        await stopper.stopForModelDeletion()
        if FileManager.default.fileExists(atPath: modelsRoot.path) {
            try FileManager.default.removeItem(at: modelsRoot)
        }
        installedKinds = []
        downloadingKind = nil
        downloadProgress = nil
        state = .notInstalled(
            missingBytes: SpeechModelCatalog.all.reduce(0) { $0 + $1.approximateBytes }
        )
    }

    private func download(
        _ descriptor: SpeechModelDescriptor,
        source: SpeechModelDownloadSource
    ) async throws {
        downloadingKind = descriptor.kind
        defer {
            downloadingKind = nil
            downloadProgress = nil
        }

        let progressHandler: @Sendable (SpeechDownloadProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                self?.state = .downloading(progress)
                self?.downloadProgress = progress
            }
        }

        if let sourceDownloader = downloader as? any SpeechModelSourceDownloading {
            _ = try await sourceDownloader.download(
                descriptor,
                source: source,
                to: modelsRoot,
                progress: progressHandler
            )
        } else if source == .huggingFace {
            _ = try await downloader.download(
                descriptor,
                to: modelsRoot,
                progress: progressHandler
            )
        } else {
            throw SpeechModelDownloadError.invalidSourceURL
        }
    }

    private func materializeSnapshot(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            throw SpeechModelImportError.invalidSnapshot
        }

        for case let item as URL in enumerator {
            let sourcePath = source.standardizedFileURL.path
            let itemPath = item.standardizedFileURL.path
            guard itemPath.hasPrefix(sourcePath) else { continue }
            let relative = String(itemPath.dropFirst(sourcePath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relative.isEmpty else { continue }
            let target = destination.appendingPathComponent(relative)
            let values = try item.resourceValues(forKeys: Set(keys))

            if values.isSymbolicLink == true {
                let resolved = item.resolvingSymlinksInPath()
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else {
                    throw SpeechModelImportError.invalidSnapshot
                }
                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: resolved, to: target)
                if isDirectory.boolValue { enumerator.skipDescendants() }
            } else if values.isDirectory == true {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: item, to: target)
            }
        }
    }

    private func updateInstalledKinds(_ locations: SpeechModelLocations) {
        installedKinds = []
        if locations.tts != nil { installedKinds.insert(.tts) }
        if locations.aligner != nil { installedKinds.insert(.aligner) }
    }

    private func state(for locations: SpeechModelLocations) -> SpeechModelState {
        if locations.isReady { return .ready(locations) }
        var missing: Int64 = 0
        if locations.tts == nil { missing += SpeechModelCatalog.tts.approximateBytes }
        if locations.aligner == nil { missing += SpeechModelCatalog.aligner.approximateBytes }
        return .notInstalled(missingBytes: missing)
    }

    private func downloadFailureMessage(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "模型下载失败：网络连接超时。"
            case .notConnectedToInternet:
                return "模型下载失败：当前没有网络连接。"
            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost:
                return "模型下载失败：无法连接下载源。"
            case .networkConnectionLost:
                return "模型下载失败：网络连接已中断。"
            default:
                return "模型下载失败：\(urlError.localizedDescription)"
            }
        }

        if let downloadError = error as? SpeechModelDownloadError {
            switch downloadError {
            case .invalidSourceURL:
                return "模型下载失败：下载源地址无效。"
            case .invalidResponse:
                return "模型下载失败：下载源返回了无效响应。"
            case .httpStatus(let status):
                return "模型下载失败：服务器返回 HTTP \(status)。"
            case .rangeUnsupported:
                return "模型下载失败：下载源不支持断点续传（Range）。"
            case .invalidContentLength(let file):
                return "模型下载失败：无法获取 \(file) 的文件大小。"
            case .incompleteFile(let file):
                return "模型下载失败：\(file) 下载不完整。"
            case .insufficientDiskSpace(let requiredBytes):
                let size = ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file)
                return "模型下载失败：磁盘空间不足，至少需要 \(size)。"
            }
        }

        return "模型下载失败：\(error.localizedDescription)"
    }

    private func importFailureMessage(_ error: Error, kind: SpeechModelKind) -> String {
        if error is SpeechModelImportError {
            let name = kind == .tts ? "TTS" : "语音对齐"
            return "模型导入失败：所选目录不是当前支持的 \(name) 模型，或文件不完整。"
        }
        return "模型导入失败：\(error.localizedDescription)"
    }
}
