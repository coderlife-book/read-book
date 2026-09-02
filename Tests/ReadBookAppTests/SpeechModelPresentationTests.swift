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
        XCTAssertEqual(row.repoID, SpeechModelCatalog.tts.repoID)
        XCTAssertEqual(row.revision, SpeechModelCatalog.tts.revision)
        XCTAssertEqual(row.license, "Apache-2.0")
        XCTAssertTrue(row.sourceURL.absoluteString.contains(SpeechModelCatalog.tts.repoID))
        XCTAssertFalse(row.byteDescription.isEmpty)
    }

    func testDownloadingRowExposesFraction() {
        let row = SpeechModelPresentation.row(
            for: .aligner,
            installedKinds: [],
            downloadingKind: .aligner,
            downloadProgress: SpeechDownloadProgress(downloadedBytes: 25, totalBytes: 100)
        )

        XCTAssertFalse(row.isInstalled)
        XCTAssertTrue(row.isDownloading)
        XCTAssertEqual(row.progressFraction ?? -1, 0.25, accuracy: 0.001)
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
    }
}
#endif
