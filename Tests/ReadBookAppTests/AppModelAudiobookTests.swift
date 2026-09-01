#if os(macOS)
import Foundation
import XCTest
@testable import ReadBook
import ReadBookCore

@MainActor
final class AppModelAudiobookTests: XCTestCase {
    func testOpeningAnotherBookStopsAudiobook() async throws {
        let fixture = try AppModelAudiobookFixture()
        try await fixture.addBook(title: "第一本", text: "第一本书的正文内容。")
        try await fixture.addBook(title: "第二本", text: "第二本书的正文内容。")
        let model = fixture.makeModel(
            controller: AudiobookController(
                preparer: fixture.preparer,
                playback: fixture.playback
            )
        )
        try await model.open(fixture.bookIDs[0])

        await model.startAudiobook()
        XCTAssertEqual(model.audiobookController?.state, .playing)

        try await model.open(fixture.bookIDs[1])
        XCTAssertEqual(model.audiobookController?.state, .idle)
    }

    func testRemovingCurrentBookStopsAudiobook() async throws {
        let fixture = try AppModelAudiobookFixture()
        try await fixture.addBook(title: "第一本", text: "第一本书的正文内容。")
        try await fixture.addBook(title: "第二本", text: "第二本书的正文内容。")
        let model = fixture.makeModel(
            controller: AudiobookController(
                preparer: fixture.preparer,
                playback: fixture.playback
            )
        )
        try await model.open(fixture.bookIDs[0])

        await model.startAudiobook()
        XCTAssertEqual(model.audiobookController?.state, .playing)

        await model.remove(bookID: fixture.bookIDs[0])
        XCTAssertEqual(model.audiobookController?.state, .idle)
    }

    func testSelectionSurvivesModelDownloadAndStartsFromSelection() async throws {
        let fixture = try AppModelAudiobookFixture(seedModels: false)
        try await fixture.addBook(title: "听书", text: "迟到那么久不说，你现在才告诉我？下一句。")
        let model = fixture.makeModel()
        try await model.open(fixture.bookIDs[0])
        let selected = (model.text as NSString).range(of: "现在")

        await model.startAudiobookFromSelection(selected)

        XCTAssertTrue(model.isAudiobookDownloadPresented)
        XCTAssertNil(model.audiobookController)

        await model.downloadAudiobookModelsAndStart()

        XCTAssertFalse(model.isAudiobookDownloading)
        XCTAssertEqual(model.audiobookController?.state, .playing)
        let blocks = await fixture.preparer.blocks
        XCTAssertEqual(blocks.first?.sentences.first?.text, "现在才告诉我？")
    }
}

@MainActor
private final class AppModelAudiobookFixture {
    let root: URL
    let repository: LibraryRepository
    let preferences: PreferencesStore
    let manager: SpeechModelManager
    let preparer = RecordingAudiobookPreparer()
    let playback = RecordingAudiobookPlayback()
    private(set) var bookIDs: [UUID] = []

    init(seedModels: Bool = true) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModelAudiobook-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        repository = LibraryRepository(paths: paths)
        preferences = PreferencesStore(
            defaults: UserDefaults(suiteName: "AppModelAudiobook.\(UUID().uuidString)")!
        )
        let modelsRoot = paths.modelsRoot
        let locator = SpeechModelLocator(ownedRoot: modelsRoot, externalHubRoots: [])
        if seedModels {
            try SpeechSnapshotWriter.writeAll(to: modelsRoot)
        }
        manager = SpeechModelManager(
            locator: locator,
            downloader: SnapshotWritingAudiobookDownloader(root: modelsRoot),
            stopper: RecordingAudiobookStopper(),
            modelsRoot: modelsRoot
        )
    }

    func addBook(title: String, text: String) async throws {
        let directory = root.appendingPathComponent("Import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(title).txt")
        try Data(text.utf8).write(to: url)
        let book = try await repository.importBook(from: url)
        bookIDs.append(book.id)
    }

    func makeModel(controller: AudiobookController? = nil) -> AppModel {
        AppModel(
            repository: repository,
            preferencesStore: preferences,
            audiobookController: controller,
            speechModelManager: manager,
            audiobookFactory: { [preparer, playback] _ in
                AudiobookController(preparer: preparer, playback: playback)
            }
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor RecordingAudiobookPreparer: SpeechPreparing {
    private(set) var blocks: [SpeechBlock] = []

    func prepare(
        _ block: SpeechBlock,
        generation: SpeechGenerationID
    ) async throws -> PreparedSpeechBlock {
        blocks.append(block)
        return PreparedSpeechBlock(sentences: block.sentences.map {
            PreparedSentence(sentence: $0, samples: [0, 0, 0], sampleRate: 24_000)
        })
    }
}

@MainActor
private final class RecordingAudiobookPlayback: AudiobookPlaybackControlling {
    private(set) var state: SpeechPlaybackState = .idle
    private(set) var currentSentenceRange: Range<Int>?
    var onSentenceFinished: (() -> Void)?
    private var queued: [PreparedSentence] = []

    func enqueue(_ sentence: PreparedSentence) {
        queued.append(sentence)
    }

    func play() {
        state = .playing
        currentSentenceRange = queued.first?.sentence.utf16Range
    }

    func pause() { state = .paused }

    func stop() {
        state = .idle
        currentSentenceRange = nil
        queued.removeAll()
    }

    func setRate(_: Double) {}
}

private actor RecordingAudiobookStopper: SpeechPlaybackStopping {
    private(set) var stopCount = 0

    func stopForModelDeletion() async {
        stopCount += 1
    }
}

private actor SnapshotWritingAudiobookDownloader: SpeechModelDownloading {
    let root: URL

    init(root: URL) {
        self.root = root
    }

    func download(
        _ descriptor: SpeechModelDescriptor,
        to modelsRoot: URL,
        progress: @Sendable (SpeechDownloadProgress) -> Void
    ) async throws -> URL {
        try SpeechSnapshotWriter.write(descriptor, to: modelsRoot)
        let total = descriptor.requiredRelativePaths.reduce(Int64(0)) { $0 + Int64($1.utf8.count) }
        progress(SpeechDownloadProgress(downloadedBytes: total, totalBytes: total))
        return modelsRoot
            .appendingPathComponent(descriptor.kind.rawValue, isDirectory: true)
            .appendingPathComponent(descriptor.revision, isDirectory: true)
    }
}

private enum SpeechSnapshotWriter {
    static func writeAll(to modelsRoot: URL) throws {
        for descriptor in SpeechModelCatalog.all {
            try write(descriptor, to: modelsRoot)
        }
    }

    static func write(_ descriptor: SpeechModelDescriptor, to modelsRoot: URL) throws {
        let snapshot = modelsRoot
            .appendingPathComponent(descriptor.kind.rawValue, isDirectory: true)
            .appendingPathComponent(descriptor.revision, isDirectory: true)
        for relativePath in descriptor.requiredRelativePaths {
            let file = snapshot.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if relativePath == "model.safetensors.index.json" {
                try JSONSerialization.data(
                    withJSONObject: ["weight_map": ["layer": "model.safetensors"]]
                ).write(to: file)
            } else {
                try Data(relativePath.utf8).write(to: file)
            }
        }
    }
}
#endif
