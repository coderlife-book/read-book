import AppKit
import Observation
import ReadBookCore

@MainActor
enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate(AppVersion)
    case available(GitHubRelease)
    case downloading(GitHubRelease)
    case validating(GitHubRelease)
    case installing(AppVersion)
    case error(String)
}

enum UpdateControllerError: LocalizedError, Equatable {
    case flushTimedOut

    var errorDescription: String? {
        switch self {
        case .flushTimedOut:
            "保存阅读进度超时。更新会继续安装，最多可能丢失最后少量未落盘的阅读进度。"
        }
    }
}

@MainActor
private final class UpdateFlushGate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false

    func install(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<Void, Error>) {
        guard !finished, let continuation else { return }
        finished = true
        self.continuation = nil
        continuation.resume(with: result)
    }
}

@MainActor
@Observable
final class UpdateController {
    private(set) var state: UpdateState = .idle
    private(set) var isPresented = false

    private let client: any UpdateReleaseProviding
    private let installer: UpdateInstaller
    private let currentVersionProvider: () -> AppVersion
    private let currentAppURLProvider: () -> URL
    private var availableRelease: GitHubRelease?
    private var automaticCheckTask: Task<Void, Never>?
    private let flushTimeout: Duration
    private var flushHandler: (@MainActor () async -> Void) = {}
    private var terminateHandler: (@MainActor () -> Void) = { NSApp.terminate(nil) }

    init(
        client: any UpdateReleaseProviding = GitHubReleaseClient(),
        installer: UpdateInstaller = UpdateInstaller(),
        currentVersionProvider: @escaping () -> AppVersion = {
            let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
            return AppVersion(raw) ?? AppVersion("0.0.0")!
        },
        currentAppURLProvider: @escaping () -> URL = { Bundle.main.bundleURL },
        flushTimeout: Duration = .seconds(10)
    ) {
        self.client = client
        self.installer = installer
        self.currentVersionProvider = currentVersionProvider
        self.currentAppURLProvider = currentAppURLProvider
        self.flushTimeout = flushTimeout
    }

    func configureLifecycle(
        flush: @escaping @MainActor () async -> Void,
        terminate: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }
    ) {
        flushHandler = flush
        terminateHandler = terminate
    }

    func scheduleAutomaticCheck() {
        guard automaticCheckTask == nil else { return }
        automaticCheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await self?.check(manual: false)
        }
    }

    func cancelAutomaticCheck() {
        automaticCheckTask?.cancel()
        automaticCheckTask = nil
    }

    func check(manual: Bool) async {
        if manual { isPresented = true }
        state = .checking
        do {
            let release = try await client.latestRelease()
            guard let latest = release.latestVersion,
                  release.archiveAsset != nil,
                  release.checksumAsset != nil else {
                throw GitHubReleaseClientError.badResponse
            }
            let current = currentVersionProvider()
            if latest > current {
                availableRelease = release
                state = .available(release)
                isPresented = manual
            } else {
                availableRelease = nil
                state = manual ? .upToDate(current) : .idle
            }
        } catch {
            availableRelease = nil
            state = manual ? .error(error.localizedDescription) : .idle
        }
    }

    func downloadAndInstall() async {
        guard !isInstallationInProgress else { return }
        guard let release = availableRelease,
              let latest = release.latestVersion,
              let archive = release.archiveAsset,
              let checksum = release.checksumAsset else {
            state = .error("当前没有可安装的更新。")
            isPresented = true
            return
        }

        state = .downloading(release)
        isPresented = true
        do {
            let checksumBytes = try await client.data(from: checksum.browserDownloadURL)
            let zipURL = try await client.download(from: archive.browserDownloadURL)
            state = .validating(release)
            try await UpdateChecksum.verifyInBackground(fileURL: zipURL, checksumData: checksumBytes)

            let candidate = try await installer.extractArchive(zipURL)
            try await installer.validateCandidate(appURL: candidate, expectedVersion: latest)

            let currentApp = currentAppURLProvider()
            guard currentApp.pathExtension.lowercased() == "app" else {
                throw UpdateInstallerError.destinationNotWritable
            }
            let helper = try installer.prepareReplacement(
                candidateAppURL: candidate,
                currentAppURL: currentApp,
                currentPID: ProcessInfo.processInfo.processIdentifier
            )

            state = .installing(latest)
            do {
                try await flushForUpdate()
            } catch UpdateControllerError.flushTimedOut {
                // Reading progress is already debounced. Do not hold a verified
                // application update hostage to one final non-cooperative save.
            }
            try installer.launchReplacementHelper(helper)
            terminateHandler()
        } catch {
            state = .error(error.localizedDescription)
            isPresented = true
        }
    }

    private var isInstallationInProgress: Bool {
        switch state {
        case .downloading, .validating, .installing:
            true
        default:
            false
        }
    }

    func flushForUpdate() async throws {
        let timeout = flushTimeout
        let flush = flushHandler
        let gate = UpdateFlushGate()

        try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)

            Task { @MainActor in
                await flush()
                gate.finish(.success(()))
            }

            Task { @MainActor in
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }
                gate.finish(.failure(UpdateControllerError.flushTimedOut))
            }
        }
    }

    func dismiss() {
        isPresented = false
        if case .error = state { state = .idle }
        if case .upToDate = state { state = .idle }
    }
}
