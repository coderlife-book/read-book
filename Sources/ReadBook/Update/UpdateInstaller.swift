import Foundation
import ReadBookCore

enum UpdateInstallerError: LocalizedError {
    case extractionFailed(String)
    case candidateMissing
    case invalidBundleIdentifier
    case invalidVersion
    case invalidSignature(String)
    case destinationNotWritable
    case helperLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let detail): "更新包解压失败。\(detail)"
        case .candidateMissing: "更新包里没有找到 ReadBook.app。"
        case .invalidBundleIdentifier: "更新包不是有效的 ReadBook 应用。"
        case .invalidVersion: "更新包版本与发布版本不一致。"
        case .invalidSignature(let detail): "更新包签名校验失败。\(detail)"
        case .destinationNotWritable: "ReadBook 当前所在目录不可写，无法自动替换。请把 App 放到你有写入权限的 Applications 或其他目录后再试。"
        case .helperLaunchFailed(let detail): "无法启动更新安装程序。\(detail)"
        }
    }
}

@MainActor
final class UpdateInstaller {
    private let fileManager: FileManager
    private let commandRunner: any UpdateCommandRunning

    init(
        fileManager: FileManager = .default,
        commandRunner: any UpdateCommandRunning = UpdateBackgroundWorker()
    ) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
    }

    func extractArchive(_ archiveURL: URL) async throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("ReadBookCandidate-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = try await commandRunner.runProcess(
            "/usr/bin/ditto",
            ["-x", "-k", archiveURL.path, directory.path]
        )
        guard result.status == 0 else {
            throw UpdateInstallerError.extractionFailed(result.stderr)
        }
        return try locateCandidate(in: directory)
    }

    func validateCandidate(appURL: URL, expectedVersion: AppVersion) async throws {
        guard let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == "com.coderlife.readbook" else {
            throw UpdateInstallerError.invalidBundleIdentifier
        }
        guard let versionText = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let version = AppVersion(versionText),
              version == expectedVersion else {
            throw UpdateInstallerError.invalidVersion
        }
        guard let executableURL = bundle.executableURL,
              fileManager.fileExists(atPath: executableURL.path) else {
            throw UpdateInstallerError.candidateMissing
        }
        let result = try await commandRunner.runProcess(
            "/usr/bin/codesign",
            ["--verify", "--deep", "--strict", "--verbose=2", appURL.path]
        )
        guard result.status == 0 else {
            throw UpdateInstallerError.invalidSignature(result.stderr)
        }
    }

    func prepareReplacement(
        candidateAppURL: URL,
        currentAppURL: URL,
        currentPID: Int32
    ) throws -> URL {
        let parent = currentAppURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: parent.path) else {
            throw UpdateInstallerError.destinationNotWritable
        }

        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("ReadBookInstaller-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent("install.sh")
        let current = shellQuote(currentAppURL.path)
        let candidate = shellQuote(candidateAppURL.path)
        let backup = shellQuote(currentAppURL.path + ".ReadBook.backup")
        let script = """
        #!/bin/sh
        set -u
        PID=\(currentPID)
        CURRENT=\(current)
        CANDIDATE=\(candidate)
        BACKUP=\(backup)
        WAIT_TICKS=0
        MAX_WAIT_TICKS=150

        while /bin/kill -0 "$PID" 2>/dev/null; do
          if [ "$WAIT_TICKS" -ge "$MAX_WAIT_TICKS" ]; then
            exit 20
          fi
          /bin/sleep 0.2
          WAIT_TICKS=$((WAIT_TICKS + 1))
        done

        /bin/rm -rf "$BACKUP"
        if [ -e "$CURRENT" ]; then
          /bin/mv "$CURRENT" "$BACKUP" || exit 21
        fi

        if /usr/bin/ditto "$CANDIDATE" "$CURRENT"; then
          /bin/rm -rf "$BACKUP"
          /usr/bin/open "$CURRENT"
          exit 0
        fi

        /bin/rm -rf "$CURRENT"
        if [ -e "$BACKUP" ]; then
          /bin/mv "$BACKUP" "$CURRENT"
          /usr/bin/open "$CURRENT"
        fi
        exit 22
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    func launchReplacementHelper(_ scriptURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw UpdateInstallerError.helperLaunchFailed(error.localizedDescription)
        }
    }

    private func locateCandidate(in directory: URL) throws -> URL {
        let direct = directory.appendingPathComponent("ReadBook.app", isDirectory: true)
        if fileManager.fileExists(atPath: direct.path) { return direct }
        if let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let url as URL in enumerator where url.lastPathComponent == "ReadBook.app" {
                return url
            }
        }
        throw UpdateInstallerError.candidateMissing
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
