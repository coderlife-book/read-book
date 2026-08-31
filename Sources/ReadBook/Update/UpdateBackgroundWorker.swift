import Darwin
import Foundation

struct UpdateProcessResult: Sendable, Equatable {
    let status: Int32
    let stderr: String
}

enum UpdateBackgroundWorkerError: LocalizedError, Equatable, Sendable {
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let executable):
            "更新校验进程超时，已终止：\(executable)"
        }
    }
}

@MainActor
protocol UpdateCommandRunning {
    func runProcess(_ executable: String, _ arguments: [String]) async throws -> UpdateProcessResult
}

struct UpdateBackgroundWorker: Sendable, UpdateCommandRunning {
    private let timeoutSeconds: TimeInterval

    init(timeoutSeconds: TimeInterval = 60) {
        self.timeoutSeconds = max(timeoutSeconds, 0.05)
    }

    func runProcess(_ executable: String, _ arguments: [String]) async throws -> UpdateProcessResult {
        let timeoutSeconds = self.timeoutSeconds
        return try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let stderrURL = fileManager.temporaryDirectory
                .appendingPathComponent("ReadBookUpdaterStderr-\(UUID().uuidString).log")
            try Data().write(to: stderrURL, options: .atomic)
            let stderrHandle = try FileHandle(forWritingTo: stderrURL)
            defer {
                try? stderrHandle.close()
                try? fileManager.removeItem(at: stderrURL)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = stderrHandle
            try process.run()

            let deadline = Date().addingTimeInterval(timeoutSeconds)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }

            guard !process.isRunning else {
                process.terminate()
                let graceDeadline = Date().addingTimeInterval(0.20)
                while process.isRunning && Date() < graceDeadline {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                if process.isRunning {
                    _ = Darwin.kill(process.processIdentifier, SIGKILL)
                }
                process.waitUntilExit()
                throw UpdateBackgroundWorkerError.timedOut(executable)
            }

            process.waitUntilExit()
            try stderrHandle.synchronize()
            try stderrHandle.close()
            let data = try Data(contentsOf: stderrURL)
            return UpdateProcessResult(
                status: process.terminationStatus,
                stderr: String(data: data, encoding: .utf8) ?? ""
            )
        }.value
    }
}
