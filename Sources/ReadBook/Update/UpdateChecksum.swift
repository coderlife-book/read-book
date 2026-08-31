import CryptoKit
import Foundation

enum UpdateChecksumError: LocalizedError {
    case invalidChecksumFile
    case mismatch

    var errorDescription: String? {
        switch self {
        case .invalidChecksumFile: "更新校验文件无效。"
        case .mismatch: "更新文件校验失败，已取消安装。"
        }
    }
}

enum UpdateChecksum {
    static func expectedDigest(from data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw UpdateChecksumError.invalidChecksumFile
        }
        guard let token = text.split(whereSeparator: { $0.isWhitespace }).first else {
            throw UpdateChecksumError.invalidChecksumFile
        }
        let value = token.lowercased()
        guard value.count == 64, value.allSatisfy({ $0.isHexDigit }) else {
            throw UpdateChecksumError.invalidChecksumFile
        }
        return value
    }

    static func sha256(of fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func verify(fileURL: URL, checksumData: Data) throws {
        let expected = try expectedDigest(from: checksumData)
        guard try sha256(of: fileURL) == expected else {
            throw UpdateChecksumError.mismatch
        }
    }

    static func verifyInBackground(fileURL: URL, checksumData: Data) async throws {
        try await Task.detached(priority: .utility) {
            try verify(fileURL: fileURL, checksumData: checksumData)
        }.value
    }
}
