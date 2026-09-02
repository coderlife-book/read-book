import Foundation

enum SpeechModelKind: String, CaseIterable, Sendable {
    case tts
    case aligner
}

struct SpeechModelDescriptor: Equatable, Sendable {
    let kind: SpeechModelKind
    let repoID: String
    let revision: String
    let approximateBytes: Int64
    let requiredRelativePaths: [String]

    var huggingFaceCacheName: String {
        "models--" + repoID.replacingOccurrences(of: "/", with: "--")
    }
}

enum SpeechModelCatalog {
    static let tts = SpeechModelDescriptor(
        kind: .tts,
        repoID: "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit",
        revision: "41d3337e8b7f2843a75841595fc14e4b9a7a4b96",
        approximateBytes: 3_080_141_538,
        requiredRelativePaths: [
            "config.json",
            "generation_config.json",
            "merges.txt",
            "model.safetensors",
            "model.safetensors.index.json",
            "preprocessor_config.json",
            "speech_tokenizer/config.json",
            "speech_tokenizer/configuration.json",
            "speech_tokenizer/model.safetensors",
            "speech_tokenizer/preprocessor_config.json",
            "tokenizer_config.json",
            "vocab.json",
        ]
    )

    static let aligner = SpeechModelDescriptor(
        kind: .aligner,
        repoID: "mlx-community/Qwen3-ForcedAligner-0.6B-4bit",
        revision: "2f652af86ae0c73fe189b9429225c908ce4bf020",
        approximateBytes: 975_854_832,
        requiredRelativePaths: [
            "chat_template.json",
            "config.json",
            "generation_config.json",
            "merges.txt",
            "model.safetensors",
            "model.safetensors.index.json",
            "preprocessor_config.json",
            "tokenizer_config.json",
            "vocab.json",
        ]
    )

    static let all = [tts, aligner]

    static func descriptor(for kind: SpeechModelKind) -> SpeechModelDescriptor {
        switch kind {
        case .tts: tts
        case .aligner: aligner
        }
    }
}
