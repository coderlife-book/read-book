import Foundation

struct SpeechModelRowPresentation: Equatable {
    let kind: SpeechModelKind
    let name: String
    let repoID: String
    let revision: String
    let license: String
    let sourceURL: URL
    let approximateBytes: Int64
    let isInstalled: Bool
    let isDownloading: Bool
    let progressFraction: Double?
    let downloadProgressDescription: String?

    var byteDescription: String {
        ByteCountFormatter.string(fromByteCount: approximateBytes, countStyle: .file)
    }
}

enum SpeechModelPresentation {
    static func row(
        for kind: SpeechModelKind,
        installedKinds: Set<SpeechModelKind>,
        downloadingKind: SpeechModelKind?,
        downloadProgress: SpeechDownloadProgress?
    ) -> SpeechModelRowPresentation {
        let descriptor = kind == .tts ? SpeechModelCatalog.tts : SpeechModelCatalog.aligner
        let activeProgress = downloadingKind == kind ? downloadProgress : nil
        return SpeechModelRowPresentation(
            kind: kind,
            name: kind == .tts ? "TTS 语音模型" : "时间对齐模型",
            repoID: descriptor.repoID,
            revision: descriptor.revision,
            license: "Apache-2.0",
            sourceURL: URL(
                string: "https://huggingface.co/\(descriptor.repoID)/tree/\(descriptor.revision)"
            )!,
            approximateBytes: descriptor.approximateBytes,
            isInstalled: installedKinds.contains(kind),
            isDownloading: downloadingKind == kind,
            progressFraction: activeProgress.map {
                Double($0.downloadedBytes) / Double(max($0.totalBytes, 1))
            },
            downloadProgressDescription: activeProgress.map(downloadDescription)
        )
    }

    private static func downloadDescription(_ progress: SpeechDownloadProgress) -> String {
        let downloaded = ByteCountFormatter.string(
            fromByteCount: progress.downloadedBytes,
            countStyle: .file
        )
        let total = ByteCountFormatter.string(
            fromByteCount: progress.totalBytes,
            countStyle: .file
        )
        let fraction = Double(progress.downloadedBytes) / Double(max(progress.totalBytes, 1))
        let percent = min(max(Int((fraction * 100).rounded()), 0), 100)
        let transfer = "\(downloaded) / \(total) · \(percent)%"

        guard let bytesPerSecond = progress.bytesPerSecond, bytesPerSecond > 0 else {
            return transfer
        }
        let speed = ByteCountFormatter.string(
            fromByteCount: Int64(bytesPerSecond.rounded()),
            countStyle: .file
        )
        return "\(speed)/s · \(transfer)"
    }
}
