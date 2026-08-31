import Foundation
import XCTest
@testable import ReadBookCore

final class UpdateMetadataTests: XCTestCase {
    func testSemanticVersionOrdersNumericComponents() throws {
        XCTAssertGreaterThan(try XCTUnwrap(AppVersion("0.1.10")), try XCTUnwrap(AppVersion("0.1.9")))
        XCTAssertEqual(AppVersion("v0.1.3"), AppVersion("0.1.3"))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("0.1.3")), try XCTUnwrap(AppVersion("0.2.0")))
        XCTAssertNil(AppVersion("banana"))
    }

    func testGitHubReleaseDecodesAndSelectsExactAssets() throws {
        let json = #"{"tag_name":"v0.1.4","name":"ReadBook v0.1.4","body":"fixes","assets":[{"name":"ReadBook-macOS.zip","browser_download_url":"https://github.com/coderlife-book/read-book/releases/download/v0.1.4/ReadBook-macOS.zip"},{"name":"ReadBook-macOS.zip.sha256","browser_download_url":"https://github.com/coderlife-book/read-book/releases/download/v0.1.4/ReadBook-macOS.zip.sha256"}]}"#
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        XCTAssertEqual(release.latestVersion, AppVersion("0.1.4"))
        XCTAssertEqual(release.archiveAsset?.name, "ReadBook-macOS.zip")
        XCTAssertEqual(release.checksumAsset?.name, "ReadBook-macOS.zip.sha256")
        XCTAssertEqual(release.releaseNotes, "fixes")
    }
}
