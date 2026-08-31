import Foundation

public struct GitHubReleaseAsset: Codable, Equatable, Sendable {
    public let name: String
    public let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

public struct GitHubRelease: Codable, Equatable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case assets
    }

    public var latestVersion: AppVersion? { AppVersion(tagName) }
    public var archiveAsset: GitHubReleaseAsset? {
        assets.first { $0.name == "ReadBook-macOS.zip" }
    }
    public var checksumAsset: GitHubReleaseAsset? {
        assets.first { $0.name == "ReadBook-macOS.zip.sha256" }
    }
    public var releaseNotes: String { body ?? "" }
}
