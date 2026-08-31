import Darwin
import Dispatch
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
            let terminated = DispatchSemaphore(value: 0)
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = stderrHandle
            process.terminationHandler = { _ in terminated.signal() }
            try process.run()

            let deadline = DispatchTime.now() + timeoutSeconds
            guard terminated.wait(timeout: deadline) == .success else {
                process.terminate()
                if terminated.wait(timeout: .now() + 0.20) == .timedOut {
                    _ = Darwin.kill(process.processIdentifier, SIGKILL)
                    _ = terminated.wait(timeout: .now() + 1.0)
                }
                throw UpdateBackgroundWorkerError.timedOut(executable)
            }

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
