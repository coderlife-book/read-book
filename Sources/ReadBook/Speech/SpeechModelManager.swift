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
            state = .failed("听书模型校验失败。")
        }
    }

    func prepareMissingModels() async {
        state = .discovering
        do {
            var locations = try locator.locateAll()
            updateInstalledKinds(locations)
            for descriptor in SpeechModelCatalog.all {
                let isPresent = descriptor.kind == .tts ? locations.tts != nil : locations.aligner != nil
                guard !isPresent else { continue }
                downloadingKind = descriptor.kind
                _ = try await downloader.download(descriptor, to: modelsRoot) { [weak self] progress in
                    Task { @MainActor in
                        self?.state = .downloading(progress)
                        self?.downloadProgress = progress
                    }
                }
                downloadingKind = nil
                downloadProgress = nil
                locations = try locator.locateAll()
                updateInstalledKinds(locations)
            }
            state = state(for: locations)
        } catch is CancellationError {
            await discover()
        } catch {
            state = .failed("听书模型下载失败，请稍后重试。")
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
}
