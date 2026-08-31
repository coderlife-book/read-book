import Foundation
import ReadBookCore

@MainActor
protocol UpdateReleaseProviding: AnyObject {
    func latestRelease() async throws -> GitHubRelease
    func data(from assetURL: URL) async throws -> Data
    func download(from assetURL: URL) async throws -> URL
}

enum GitHubReleaseClientError: LocalizedError {
    case badResponse
    case untrustedURL

    var errorDescription: String? {
        switch self {
        case .badResponse: "无法读取更新信息。"
        case .untrustedURL: "更新下载地址不受信任。"
        }
    }
}

@MainActor
final class GitHubReleaseClient: UpdateReleaseProviding {
    private let session: URLSession
    private let latestURL = URL(string: "https://api.github.com/repos/coderlife-book/read-book/releases/latest")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func latestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ReadBook-macOS-Updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitHubReleaseClientError.badResponse
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    func data(from assetURL: URL) async throws -> Data {
        try validate(assetURL)
        var request = URLRequest(url: assetURL)
        request.setValue("ReadBook-macOS-Updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GitHubReleaseClientError.badResponse
        }
        return data
    }

    func download(from assetURL: URL) async throws -> URL {
        try validate(assetURL)
        var request = URLRequest(url: assetURL)
        request.setValue("ReadBook-macOS-Updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120
        let (temporaryURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GitHubReleaseClientError.badResponse
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadBookUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("ReadBook-macOS.zip")
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func validate(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "github.com" || host == "api.github.com" else {
            throw GitHubReleaseClientError.untrustedURL
        }
    }
}
