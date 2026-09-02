#if os(macOS)
import XCTest
@testable import ReadBook

final class SpeechModelPresentationTests: XCTestCase {
    func testInstalledRowShowsSourceRevisionAndLicense() {
        let row = SpeechModelPresentation.row(
            for: .tts,
            installedKinds: [.tts],
            downloadingKind: nil,
            downloadProgress: nil
        )

        XCTAssertTrue(row.isInstalled)
        XCTAssertFalse(row.isDownloading)
        XCTAssertNil(row.progressFraction)
        XCTAssertNil(row.downloadProgressDescription)
        XCTAssertEqual(row.repoID, SpeechModelCatalog.tts.repoID)
        XCTAssertEqual(row.revision, SpeechModelCatalog.tts.revision)
        XCTAssertEqual(row.license, "Apache-2.0")
        XCTAssertTrue(row.sourceURL.absoluteString.contains(SpeechModelCatalog.tts.repoID))
        XCTAssertFalse(row.byteDescription.isEmpty)
    }

    func testDownloadingRowExposesFractionAndTransferDetails() throws {
        let row = SpeechModelPresentation.row(
            for: .aligner,
            installedKinds: [],
            downloadingKind: .aligner,
            downloadProgress: SpeechDownloadProgress(
                downloadedBytes: 326_000_000,
                totalBytes: 3_080_000_000,
                bytesPerSecond: 8_600_000
            )
        )

        XCTAssertFalse(row.isInstalled)
        XCTAssertTrue(row.isDownloading)
        XCTAssertEqual(row.progressFraction ?? -1, 326.0 / 3_080.0, accuracy: 0.001)
        let description = try XCTUnwrap(row.downloadProgressDescription)
        XCTAssertTrue(description.contains("/s"), description)
        XCTAssertTrue(description.contains(" / "), description)
        XCTAssertTrue(description.contains("%"), description)
        XCTAssertTrue(description.contains("·"), description)
    }

    func testDownloadingRowStillShowsBytesBeforeSpeedCanBeMeasured() throws {
        let row = SpeechModelPresentation.row(
            for: .tts,
            installedKinds: [],
            downloadingKind: .tts,
            downloadProgress: SpeechDownloadProgress(
                downloadedBytes: 12_000_000,
                totalBytes: 3_080_000_000,
                bytesPerSecond: nil
            )
        )

        let description = try XCTUnwrap(row.downloadProgressDescription)
        XCTAssertFalse(description.contains("/s"), description)
        XCTAssertTrue(description.contains(" / "), description)
        XCTAssertTrue(description.contains("%"), description)
    }

    func testOtherKindIsNotMarkedDownloading() {
        let row = SpeechModelPresentation.row(
            for: .tts,
            installedKinds: [],
            downloadingKind: .aligner,
            downloadProgress: SpeechDownloadProgress(downloadedBytes: 1, totalBytes: 2)
        )

        XCTAssertFalse(row.isDownloading)
        XCTAssertNil(row.progressFraction)
        XCTAssertNil(row.downloadProgressDescription)
    }
}
#endif
