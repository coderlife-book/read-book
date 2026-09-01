import Foundation
import Observation
import ReadBookCore

@MainActor
@Observable
final class AppModel {
    let repository: LibraryRepository
    let session: ReaderSession
    private(set) var audiobookController: AudiobookController?
    private let preferencesStore: PreferencesStore

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
        audiobookController: AudiobookController? = nil
    ) {
        self.repository = repository
        self.preferencesStore = preferencesStore
        self.audiobookController = audiobookController
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

        let paths = AppPaths()
        let locator = SpeechModelLocator(
            ownedRoot: paths.modelsRoot,
            externalHubRoots: [
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
            ]
        )
        guard let locations = try? locator.locateAll(), locations.isReady else {
            isAudiobookDownloadPresented = true
            return
        }
        configureAudiobook(locations)
        await audiobookController?.startFromReadingPosition(text: text, position: position)
    }

    func downloadAudiobookModelsAndStart() async {
        guard !isAudiobookDownloading else { return }
        isAudiobookDownloading = true
        defer { isAudiobookDownloading = false }

        let paths = AppPaths()
        let locator = SpeechModelLocator(
            ownedRoot: paths.modelsRoot,
            externalHubRoots: []
        )
        do {
            let downloader = SpeechModelDownloader()
            var locations = try locator.locateAll()
            for descriptor in SpeechModelCatalog.all {
                let present = descriptor.kind == .tts ? locations.tts != nil : locations.aligner != nil
                guard !present else { continue }
                _ = try await downloader.download(descriptor, to: paths.modelsRoot) { _ in }
                locations = try locator.locateAll()
            }
            guard locations.isReady else { throw SpeechPipelineError.missingTTSModel }
            configureAudiobook(locations)
            await audiobookController?.startFromReadingPosition(text: text, position: position)
        } catch {
            lastErrorMessage = "听书模型下载失败，请稍后重试。"
        }
    }

    private func configureAudiobook(_ locations: SpeechModelLocations) {
        let controller = AudiobookController(preparer: MLXSpeechPipeline(locations: locations), playback: SpeechPlaybackController())
        controller.onPositionChange = { [weak self] position in
            self?.updatePosition(position)
        }
        audiobookController = controller
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
