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
    case installing(AppVersion)
    case error(String)
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
    private var flushHandler: (@MainActor () async -> Void) = {}
    private var terminateHandler: (@MainActor () -> Void) = { NSApp.terminate(nil) }

    init(
        client: any UpdateReleaseProviding = GitHubReleaseClient(),
        installer: UpdateInstaller = UpdateInstaller(),
        currentVersionProvider: @escaping () -> AppVersion = {
            let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
            return AppVersion(raw) ?? AppVersion("0.0.0")!
        },
        currentAppURLProvider: @escaping () -> URL = { Bundle.main.bundleURL }
    ) {
        self.client = client
        self.installer = installer
        self.currentVersionProvider = currentVersionProvider
        self.currentAppURLProvider = currentAppURLProvider
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
                isPresented = true
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
            // These operations intentionally stay on the controller's MainActor
            // boundary. `async let` would spawn child tasks and force the
            // non-Sendable update provider across actor isolation under Swift 6.
            let checksumBytes = try await client.data(from: checksum.browserDownloadURL)
            let zipURL = try await client.download(from: archive.browserDownloadURL)
            try UpdateChecksum.verify(fileURL: zipURL, checksumData: checksumBytes)

            let candidate = try installer.extractArchive(zipURL)
            try installer.validateCandidate(appURL: candidate, expectedVersion: latest)

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
            await flushHandler()
            try installer.launchReplacementHelper(helper)
            terminateHandler()
        } catch {
            state = .error(error.localizedDescription)
            isPresented = true
        }
    }

    func dismiss() {
        isPresented = false
        if case .error = state { state = .idle }
        if case .upToDate = state { state = .idle }
    }
}
