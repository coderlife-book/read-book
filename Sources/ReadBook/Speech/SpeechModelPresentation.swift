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
            progressFraction: downloadingKind == kind
                ? downloadProgress.map {
                    Double($0.downloadedBytes) / Double(max($0.totalBytes, 1))
                }
                : nil
        )
    }
}
