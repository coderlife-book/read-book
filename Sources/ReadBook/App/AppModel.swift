import Foundation
import Observation
import ReadBookCore

@MainActor
@Observable
final class AppModel {
    let repository: LibraryRepository
    let session: ReaderSession
    private(set) var audiobookController: AudiobookController?
    private(set) var speechModelManager: SpeechModelManager?
    private let preferencesStore: PreferencesStore
    private let audiobookFactory: @MainActor (SpeechModelLocations) -> AudiobookController
    private var pendingAudiobookSelection: NSRange?
    private var audiobookDownloadTask: Task<Void, Never>?

    var books: [BookMetadata] = []
    var preferences: ReaderPreferences
    var lastErrorMessage: String?
    var isImportPresented = false
    var encodingRecoveryURL: URL?
    var sessionRevision = 0
    var isAudiobookDownloadPresented = false
    var isAudiobookDownloading = false

    init(
        repository: LibraryRepository = LibraryRepository(),
        preferencesStore: PreferencesStore = PreferencesStore(),
        audiobookController: AudiobookController? = nil,
        speechModelManager: SpeechModelManager? = nil,
        audiobookFactory: @escaping @MainActor (SpeechModelLocations) -> AudiobookController = { locations in
            AudiobookController(
                preparer: MLXSpeechPipeline(locations: locations),
                playback: SpeechPlaybackController()
            )
        }
    ) {
        self.repository = repository
        self.preferencesStore = preferencesStore
        self.audiobookController = audiobookController
        self.speechModelManager = speechModelManager
        self.audiobookFactory = audiobookFactory
        self.preferences = (try? preferencesStore.load()) ?? .defaults
        self.session = ReaderSession(repository: repository)
        self.session.setReadingMode(self.preferences.readingMode)
    }

    var currentBook: BookMetadata? { _ = sessionRevision; return session.currentBook }
    var text: String { _ = sessionRevision; return session.text }
    var position: BookPosition { _ = sessionRevision; return session.position }
    var currentChapter: Chapter? { _ = sessionRevision; return session.currentChapter }
    var readingMode: ReadingMode { _ = sessionRevision; return session.readingMode }

    var progressPercent: Int {
        guard let book = currentBook, book.totalUTF16Length > 0 else { return 0 }
        return min(max(Int((Double(position.utf16Offset) / Double(book.totalUTF16Length)) * 100), 0), 100)
    }

    var audiobookModelRows: [SpeechModelRowPresentation] {
        guard let manager = speechModelManager else { return [] }
        return SpeechModelKind.allCases.map {
            SpeechModelPresentation.row(
                for: $0,
                installedKinds: manager.installedKinds,
                downloadingKind: manager.downloadingKind,
                downloadProgress: manager.downloadProgress
            )
        }
    }

    var audiobookInstalledKinds: Set<SpeechModelKind> {
        speechModelManager?.installedKinds ?? []
    }

    var audiobookDownloadMessage: String {
        let missing = audiobookMissingBytes
        let sizeDescription = missing.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        } ?? "约 3.8 GB"
        return "首次听书需要下载 \(sizeDescription) 的本地模型。模型仅在此设备运行，不会上传小说内容。"
    }

    var audiobookDownloadFraction: Double? {
        guard case .downloading(let progress) = speechModelManager?.state else { return nil }
        return Double(progress.downloadedBytes) / Double(max(progress.totalBytes, 1))
    }

    private var audiobookMissingBytes: Int64? {
        guard case .notInstalled(let missingBytes) = speechModelManager?.state else { return nil }
        return missingBytes
    }

    func start() async {
        await reloadLibrary()
        do {
            if let id = try await repository.lastOpenedBookID() {
                try? await open(id)
            }
        } catch {
            lastErrorMessage = message(for: error)
        }
    }

    func reloadLibrary() async {
        books = ((try? await repository.loadLibrary()) ?? [])
            .sorted { $0.lastReadAt > $1.lastReadAt }
    }

    func open(_ id: UUID) async throws {
        await audiobookController?.stop(reason: .bookChanged)
        try await session.open(bookID: id)
        sessionRevision &+= 1
        await reloadLibrary()
    }

    func requestImport() {
        isImportPresented = true
    }

    func importBook(_ url: URL, override: ImportedTextEncoding? = nil) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let book = try await repository.importBook(from: url, encodingOverride: override)
            encodingRecoveryURL = nil
            await reloadLibrary()
            try await open(book.id)
        } catch TextDecoderError.undecodable {
            encodingRecoveryURL = url
            lastErrorMessage = "无法识别文本编码。你可以手动选择编码后重试。"
        } catch {
            lastErrorMessage = message(for: error)
        }
    }

    func updatePosition(_ position: BookPosition) {
        session.updatePosition(position)
        sessionRevision &+= 1
    }

    func startAudiobook() async {
        guard currentBook != nil else { return }
        if let audiobookController {
            switch audiobookController.state {
            case .playing, .paused:
                await audiobookController.togglePlayback()
            case .idle, .preparing, .buffering, .failed:
                await audiobookController.startFromReadingPosition(text: text, position: position)
            }
            return
        }

        await modelManager.discover()
        guard case .ready(let locations) = modelManager.state else {
            isAudiobookDownloadPresented = true
            return
        }
        configureAudiobook(locations)
        await audiobookController?.startFromReadingPosition(text: text, position: position)
    }

    func startAudiobookFromSelection(_ range: NSRange) async {
        guard currentBook != nil else { return }
        if let audiobookController {
            await audiobookController.startFromSelection(range, text: text)
            return
        }

        pendingAudiobookSelection = range
        await modelManager.discover()
        guard case .ready(let locations) = modelManager.state else {
            isAudiobookDownloadPresented = true
            return
        }
        configureAudiobook(locations)
        await audiobookController?.startFromSelection(range, text: text)
    }

    func beginAudiobookDownload() {
        guard !isAudiobookDownloading else { return }
        isAudiobookDownloadPresented = false
        audiobookDownloadTask?.cancel()
        audiobookDownloadTask = Task { @MainActor [weak self] in
            await self?.downloadAudiobookModelsAndStart()
        }
    }

    func cancelAudiobookDownload() {
        audiobookDownloadTask?.cancel()
        audiobookDownloadTask = nil
        isAudiobookDownloading = false
        pendingAudiobookSelection = nil
    }

    func downloadAudiobookModelsAndStart() async {
        guard !isAudiobookDownloading else { return }
        isAudiobookDownloading = true
        defer {
            isAudiobookDownloading = false
            pendingAudiobookSelection = nil
        }

        let selection = pendingAudiobookSelection
        await modelManager.prepareMissingModels()
        guard case .ready(let locations) = modelManager.state else {
            lastErrorMessage = "听书模型下载失败，请稍后重试。"
            return
        }
        configureAudiobook(locations)
        if let selection {
            await audiobookController?.startFromSelection(selection, text: text)
        } else {
            await audiobookController?.startFromReadingPosition(text: text, position: position)
        }
    }

    func deleteAudiobookModels() async {
        do {
            try await modelManager.deleteInstalledModels()
            audiobookController = nil
            pendingAudiobookSelection = nil
        } catch {
            lastErrorMessage = "删除听书模型失败，请稍后重试。"
        }
    }

    func discoverAudiobookModels() async {
        await modelManager.discover()
    }

    private func configureAudiobook(_ locations: SpeechModelLocations) {
        let controller = audiobookFactory(locations)
        controller.onPositionChange = { [weak self] position in
            self?.session.updatePosition(position)
        }
        controller.setRate(preferences.speechRate)
        audiobookController = controller
    }

    private var modelManager: SpeechModelManager {
        if let speechModelManager { return speechModelManager }
        let manager = makeSpeechModelManager()
        speechModelManager = manager
        return manager
    }

    private func makeSpeechModelManager() -> SpeechModelManager {
        let paths = AppPaths()
        var externalRoots = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/huggingface/hub", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches/huggingface/hub", isDirectory: true),
        ]
        if let hfHome = ProcessInfo.processInfo.environment["HF_HOME"] {
            externalRoots.append(
                URL(fileURLWithPath: hfHome, isDirectory: true)
                    .appendingPathComponent("hub", isDirectory: true)
            )
        }
        return SpeechModelManager(
            locator: SpeechModelLocator(ownedRoot: paths.modelsRoot, externalHubRoots: externalRoots),
            downloader: SpeechModelDownloader(),
            stopper: AppModelAudiobookStopper(model: self),
            modelsRoot: paths.modelsRoot
        )
    }

    func jump(to chapter: Chapter) {
        Task { @MainActor [weak audiobookController] in
            await audiobookController?.stop(reason: .selectionJump)
        }
        session.jump(to: chapter)
        sessionRevision &+= 1
    }

    func setMode(_ mode: ReadingMode) {
        preferences.readingMode = mode
        session.setReadingMode(mode)
        sessionRevision &+= 1
        persistPreferences()
    }

    func rename(bookID: UUID, title: String) async {
        do {
            let isCurrent = currentBook?.id == bookID
            try await repository.rename(bookID: bookID, title: title)
            if isCurrent {
                try await session.open(bookID: bookID)
                sessionRevision &+= 1
            }
            await reloadLibrary()
        } catch {
            lastErrorMessage = message(for: error)
        }
    }

    func remove(bookID: UUID) async {
        do {
            let removingCurrent = currentBook?.id == bookID
            if removingCurrent {
                await audiobookController?.stop(reason: .bookRemoved)
                await session.flush()
            }
            try await repository.remove(bookID: bookID)
            await reloadLibrary()
            if removingCurrent {
                if let next = books.first {
                    try await open(next.id)
                } else {
                    await session.close()
                    sessionRevision &+= 1
                }
            }
        } catch {
            lastErrorMessage = message(for: error)
        }
    }

    func updatePreferences(_ mutate: (inout ReaderPreferences) -> Void) {
        mutate(&preferences)
        if session.readingMode != preferences.readingMode {
            session.setReadingMode(preferences.readingMode)
            sessionRevision &+= 1
        }
        persistPreferences()
    }

    func persistPreferences() {
        do {
            try preferencesStore.save(preferences)
        } catch {
            lastErrorMessage = "设置保存失败，请稍后重试。"
        }
    }

    func message(for error: Error) -> String {
        switch error {
        case TextDecoderError.emptyInput, LibraryError.emptyBook:
            return "这个 TXT 文件没有可阅读的内容。"
        case TextDecoderError.undecodable:
            return "无法识别文本编码。请手动选择编码后重试。"
        case LibraryError.unsupportedFileType:
            return "目前只支持导入 .txt 小说。"
        case LibraryError.missingContent:
            return "本地小说文件缺失，无法继续阅读。"
        case LibraryError.invalidTitle:
            return "书名不能为空。"
        default:
            return "读取或保存失败，请稍后重试。"
        }
    }
}

private final class AppModelAudiobookStopper: SpeechPlaybackStopping, @unchecked Sendable {
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
    }

    func stopForModelDeletion() async {
        guard let model else { return }
        await model.audiobookController?.stop(reason: .modelDeleted)
    }
}
