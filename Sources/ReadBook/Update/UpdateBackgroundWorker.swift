import Foundation

struct UpdateProcessResult: Sendable, Equatable {
    let status: Int32
    let stderr: String
}

struct UpdateBackgroundWorker: Sendable {
    func runProcess(_ executable: String, _ arguments: [String]) async throws -> UpdateProcessResult {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            return UpdateProcessResult(
                status: process.terminationStatus,
                stderr: String(data: data, encoding: .utf8) ?? ""
            )
        }.value
    }
}
