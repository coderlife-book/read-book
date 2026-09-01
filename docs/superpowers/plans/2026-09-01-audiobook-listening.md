# ReadBook 本地听书与句子高亮 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 ReadBook 增加按需下载、完全本地运行的 Serena 中文听书能力，并在分页和连续阅读中准确高亮当前句子。

**Architecture:** 使用锁定 revision 的 `mlx-audio-swift` 原生加载 Qwen3-TTS 1.7B CustomVoice 和 Qwen3 ForcedAligner；Core 负责 UTF-16 分句，App 层负责模型、生成/对齐、10/20/30 句队列和 AVAudioEngine 播放。`AudiobookController` 是唯一编排入口，文本视图只接收全局高亮范围并上报全局选区。

**Tech Stack:** Swift 6、SwiftUI、AppKit、AVFoundation、MLX Audio Swift、Swift Package Manager、XCTest

**Spec:** `docs/superpowers/specs/2026-09-01-audiobook-listening-design.md`

## Global Constraints

- 平台保持 macOS 26+，不得增加 Python、Conda、本地 HTTP 服务或云端 TTS。
- TTS 固定为 `mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit` revision `41d3337e8b7f2843a75841595fc14e4b9a7a4b96`。
- 对齐固定为 `mlx-community/Qwen3-ForcedAligner-0.6B-4bit` revision `2f652af86ae0c73fe189b9429225c908ce4bf020`。
- 声线固定为 Serena，首版不增加角色识别、多人声线、克隆或训练配置。
- 普通阅读路径不得扫描、下载或加载模型；只有首次使用听书或进入模型管理时触发。
- 两种阅读模式继续只以 `BookPosition.utf16Offset` 为权威进度。
- 倍速范围 `0.5x...1.5x`，步长 `0.1x`，默认 `1.0x`。
- 队列低水位 10 句、目标 20 句、硬上限 30 句；跳转和换书必须取消旧 generation。
- 不使用覆盖正文的透明 SwiftUI 手势层；窗口拖动、Resize、正文滚动和文本选择必须保持原生行为。
- 任何新增提交使用 `type(scope): 中文描述`；只提交当前任务相关文件。
- 每个任务先写失败测试，确认失败原因正确，再写最小实现。

## File Map

### Core

- `Sources/ReadBookCore/Speech/SpeechSentence.swift`：句子值类型、起播策略和 UTF-16 范围。
- `Sources/ReadBookCore/Speech/SentenceSegmenter.swift`：中文标点、引号、换行和组合字符分句。
- `Sources/ReadBookCore/Models/ReaderPreferences.swift`：持久化并限制听书倍速。
- `Sources/ReadBookCore/Storage/AppPaths.swift`：ReadBook 模型根目录和临时下载目录。
- `Tests/ReadBookCoreTests/SentenceSegmenterTests.swift`：分句与 UTF-16 回归测试。
- `Tests/ReadBookCoreTests/PreferencesStoreTests.swift`：倍速兼容、限制和持久化测试。

### Model Management

- `Sources/ReadBook/Speech/SpeechModelCatalog.swift`：固定 repo、revision、文件清单、容量和许可证。
- `Sources/ReadBook/Speech/SpeechModelLocator.swift`：扫描 ReadBook 与 Hugging Face 缓存并校验 snapshot。
- `Sources/ReadBook/Speech/SpeechModelDownloader.swift`：Range 续传、partial、进度和原子安装。
- `Sources/ReadBook/Speech/SpeechModelManager.swift`：面向 UI 的模型状态、准备和删除操作。
- `Tests/ReadBookAppTests/SpeechModelLocatorTests.swift`：扫描优先级与完整性。
- `Tests/ReadBookAppTests/SpeechModelDownloaderTests.swift`：下载、续传、取消和校验。
- `Tests/ReadBookAppTests/SpeechModelManagerTests.swift`：缺失容量、状态转换和删除。

### Speech Pipeline

- `Sources/ReadBook/Speech/SpeechTypes.swift`：块、PCM、对齐句、播放状态和协议。
- `Sources/ReadBook/Speech/MLXSpeechPipeline.swift`：本地 TTS 生成和 ForcedAligner 对齐。
- `Sources/ReadBook/Speech/SentenceTimingMapper.swift`：词/字时间范围合并为句级采样帧。
- `Sources/ReadBook/Speech/SpeechQueue.swift`：generation ID 与 10/20/30 水位。
- `Sources/ReadBook/Speech/SpeechPlaybackController.swift`：AVAudioEngine 播放、倍速、暂停和源帧时钟。
- `Sources/ReadBook/Speech/AudiobookController.swift`：从位置/选区起播并编排补充、播放和进度。
- `Tests/ReadBookAppTests/SpeechModelCompatibilityTests.swift`：显式启用的真实模型本地测试。
- `Tests/ReadBookAppTests/SentenceTimingMapperTests.swift`：中文对齐合并。
- `Tests/ReadBookAppTests/SpeechQueueTests.swift`：水位与旧 generation 丢弃。
- `Tests/ReadBookAppTests/SpeechPlaybackControllerTests.swift`：时间线、倍速和状态。
- `Tests/ReadBookAppTests/AudiobookControllerTests.swift`：端到端假实现编排。

### Reader Integration

- `Sources/ReadBook/Reader/SpeechSelectionPopover.swift`：锚定 NSTextView 选区的“从此处开始听”。
- `Sources/ReadBook/Reader/ContinuousTextView.swift`：全局选区映射和听书高亮。
- `Sources/ReadBook/Reader/ContinuousReaderView.swift`：向连续文本视图传递听书状态。
- `Sources/ReadBook/Reader/PagedTextView.swift`：分页局部选区和高亮。
- `Sources/ReadBook/Reader/PaginatedReaderView.swift`：PageRange 全局映射和自动翻页。
- `Tests/ReadBookAppTests/ContinuousTextViewTests.swift`：虚拟窗口中的选择和高亮。
- `Tests/ReadBookAppTests/PagedTextViewTests.swift`：PageRange 中的选择和高亮。

### UI and Lifecycle

- `Sources/ReadBook/Reader/AudiobookControlsView.swift`：播放、暂停、缓冲和倍速 popover。
- `Sources/ReadBook/Reader/AudiobookDownloadView.swift`：按需下载确认与进度。
- `Sources/ReadBook/Reader/ReaderToolbar.swift`：插入 30 × 30 pt 听书入口。
- `Sources/ReadBook/Reader/ReaderRootView.swift`：连接控制器、文本视图、下载 sheet 和浮层动作。
- `Sources/ReadBook/Settings/SettingsView.swift`：模型状态、来源、许可证和删除。
- `Sources/ReadBook/App/AppModel.swift`：拥有 `AudiobookController` 并在换书/删除时停止。
- `Sources/ReadBook/App/AppRuntime.swift`：停止时释放听书资源。
- `Sources/ReadBook/App/ReadBookApp.swift`：退出清理。
- `Tests/ReadBookAppTests/AudiobookLifecycleTests.swift`：隐藏、换书、退出行为。

---

### Task 1: Pin MLX Audio and prove the selected models load natively

**Files:**
- Modify: `Package.swift`
- Create: `Tests/ReadBookAppTests/SpeechModelCompatibilityTests.swift`

**Interfaces:**
- Consumes: local model directories supplied by `READBOOK_TTS_MODEL_DIR` and `READBOOK_ALIGNER_MODEL_DIR`.
- Produces: pinned products `MLXAudioCore`, `MLXAudioTTS`, and `MLXAudioSTT` available to the `ReadBook` target.

- [ ] **Step 1: Add the pinned package dependency and product dependencies**

Use the inspected commit, not a branch:

```swift
let mlxAudio: Package.Dependency = .package(
    url: "https://github.com/Blaizzy/mlx-audio-swift.git",
    revision: "3506fb93cc3b9e4a642079d5384eaca0373962e6"
)

let mlxProducts: [Target.Dependency] = [
    .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
    .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
    .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
]
```

Append `mlxProducts` only to the macOS `ReadBook` executable and `ReadBookAppTests`; keep `ReadBookCore` dependency-free.

- [ ] **Step 2: Write the opt-in real-model test**

```swift
#if os(macOS)
import MLXAudioSTT
import MLXAudioTTS
import XCTest

final class SpeechModelCompatibilityTests: XCTestCase {
    func testPinnedQwenModelsGenerateAndAlignChineseWhenOptedIn() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["READBOOK_RUN_SPEECH_MODEL_TESTS"] == "1" else {
            throw XCTSkip("Set READBOOK_RUN_SPEECH_MODEL_TESTS=1 for the local model test")
        }
        let ttsURL = URL(fileURLWithPath: try XCTUnwrap(env["READBOOK_TTS_MODEL_DIR"]))
        let alignerURL = URL(fileURLWithPath: try XCTUnwrap(env["READBOOK_ALIGNER_MODEL_DIR"]))
        let text = "你现在才告诉我？电话里传来一阵吼声。"

        let tts = try await Qwen3TTSModel.fromModelDirectory(ttsURL)
        let audio = try await tts.generate(
            text: text,
            voice: "Serena, 清澈、干净、少气声，像专业有声书主播一样朗读。",
            refAudio: nil,
            refText: nil,
            language: "Chinese"
        )
        XCTAssertGreaterThan(audio.size, 0)

        let aligner = try await Qwen3ForcedAlignerModel.fromModelDirectory(alignerURL)
        let result = aligner.generate(audio: audio, text: text, language: "Chinese")
        XCTAssertFalse(result.items.isEmpty)
        XCTAssertTrue(zip(result.items, result.items.dropFirst()).allSatisfy { pair in
            pair.0.endTime <= pair.1.startTime
        })
    }
}
#endif
```

If the exact upstream overload requires `generationParameters`, pass `GenerateParameters(maxTokens: 4096, temperature: 0.9, topP: 1.0, repetitionPenalty: 1.1)`; do not change model or revision to make the test pass.

- [ ] **Step 3: Run the normal suite and confirm the opt-in test skips**

Run: `swift test --filter SpeechModelCompatibilityTests`

Expected: build succeeds and test is skipped because the environment flag is absent.

- [ ] **Step 4: Download only the missing aligner into a temporary local cache**

Run from the existing isolated Python environment:

```bash
HF_HOME=/tmp/readbook-qwen3-tts/hf-home \
  /tmp/readbook-qwen3-tts/venv/bin/huggingface-cli download \
  mlx-community/Qwen3-ForcedAligner-0.6B-4bit \
  --revision 2f652af86ae0c73fe189b9429225c908ce4bf020
```

Expected: only the approximately 0.9 GB aligner downloads; the existing 1.7B TTS is untouched.

- [ ] **Step 5: Run the real-model compatibility test**

Resolve both snapshot directories, then run:

```bash
READBOOK_RUN_SPEECH_MODEL_TESTS=1 \
READBOOK_TTS_MODEL_DIR="$TTS_SNAPSHOT" \
READBOOK_ALIGNER_MODEL_DIR="$ALIGNER_SNAPSHOT" \
swift test --filter SpeechModelCompatibilityTests
```

Expected: PASS with non-empty audio and ordered alignment items. If it fails, stop here and diagnose the pinned native SDK; do not implement a Python fallback.

- [ ] **Step 6: Commit the compatibility boundary**

```bash
git add Package.swift Package.resolved Tests/ReadBookAppTests/SpeechModelCompatibilityTests.swift
git commit -m "chore(speech): 接入原生 MLX 音频依赖"
```

### Task 2: Add UTF-16 sentence segmentation and persistent speech rate

**Files:**
- Create: `Sources/ReadBookCore/Speech/SpeechSentence.swift`
- Create: `Sources/ReadBookCore/Speech/SentenceSegmenter.swift`
- Create: `Tests/ReadBookCoreTests/SentenceSegmenterTests.swift`
- Modify: `Sources/ReadBookCore/Models/ReaderPreferences.swift`
- Modify: `Tests/ReadBookCoreTests/PreferencesStoreTests.swift`

**Interfaces:**
- Produces: `SpeechSentence`, `SpeechStartPolicy`, and `SentenceSegmenter.sentences(in:startingAt:policy:limit:)`.
- Produces: `ReaderPreferences.speechRate: Double` clamped to `0.5...1.5`.

- [ ] **Step 1: Write failing segmentation tests**

```swift
func testSegmentsQuotedChineseAndPreservesUTF16Ranges() {
    let text = "“你不来了？喂，什么意思！”\n电话里传来吼声。🙂继续。"
    let result = SentenceSegmenter().sentences(
        in: text, startingAt: 0, policy: .containingSentence, limit: 20
    )
    XCTAssertEqual(result.map(\.text), ["“你不来了？", "喂，什么意思！”", "电话里传来吼声。", "🙂继续。"])
    for sentence in result {
        XCTAssertEqual((text as NSString).substring(with: sentence.nsRange), sentence.text)
    }
}

func testExactOffsetStartsAtSelectedCharacter() {
    let text = "迟到那么久不说，你现在才告诉我？下一句。"
    let offset = (text as NSString).range(of: "现在").location
    let result = SentenceSegmenter().sentences(in: text, startingAt: offset, policy: .exactOffset, limit: 20)
    XCTAssertEqual(result.first?.text, "现在才告诉我？")
    XCTAssertEqual(result.first?.utf16Range.lowerBound, offset)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter SentenceSegmenterTests`

Expected: FAIL because `SentenceSegmenter` and related types do not exist.

- [ ] **Step 3: Implement the sentence values and segmenter**

```swift
public struct SpeechSentence: Equatable, Sendable {
    public let text: String
    public let utf16Range: Range<Int>
    public var nsRange: NSRange { NSRange(location: utf16Range.lowerBound, length: utf16Range.count) }
}

public enum SpeechStartPolicy: Sendable { case containingSentence, exactOffset }

public struct SentenceSegmenter: Sendable {
    public func sentences(
        in text: String,
        startingAt rawOffset: Int,
        policy: SpeechStartPolicy,
        limit: Int
    ) -> [SpeechSentence] {
        // Work on NSString, clamp to composed-character boundaries, include closing quotes,
        // skip leading blank lines, and stop after exactly `limit` emitted sentences.
    }
}
```

Implement terminators `。！？!?` and the two-character ellipsis `……`; absorb trailing `”’」』】)` and paragraph separators into the preceding sentence only when they contain no spoken text.

- [ ] **Step 4: Add failing speech-rate compatibility tests**

```swift
func testLegacyPreferencesDecodeWithDefaultSpeechRate() throws {
    let json = #"{"readingMode":"paginated","fontFamily":"PingFang SC","fontSize":17,"lineSpacing":8,"paragraphSpacing":9,"theme":"soft","alwaysOnTop":false,"appPresenceMode":"normal"}"#
    let value = try JSONDecoder().decode(ReaderPreferences.self, from: Data(json.utf8))
    XCTAssertEqual(value.speechRate, 1.0)
}

func testSpeechRateClampsAndRoundTrips() throws {
    var value = ReaderPreferences.defaults
    value.speechRate = 1.5
    let decoded = try JSONDecoder().decode(ReaderPreferences.self, from: JSONEncoder().encode(value))
    XCTAssertEqual(decoded.speechRate, 1.5)
}
```

- [ ] **Step 5: Implement speech-rate persistence**

Add `speechRate` to the initializer with default `1.0`, CodingKeys, decode fallback, encoding, defaults, and a mutating clamp path used by `AppModel.updatePreferences`. The stored value must be `min(max(value, 0.5), 1.5)`.

- [ ] **Step 6: Run Core tests and commit**

Run: `swift test --filter SentenceSegmenterTests && swift test --filter PreferencesStoreTests`

Expected: PASS.

```bash
git add Sources/ReadBookCore Tests/ReadBookCoreTests
git commit -m "feat(speech): 增加 UTF-16 分句与倍速设置"
```

### Task 3: Discover and validate existing local model snapshots

**Files:**
- Modify: `Sources/ReadBookCore/Storage/AppPaths.swift`
- Create: `Sources/ReadBook/Speech/SpeechModelCatalog.swift`
- Create: `Sources/ReadBook/Speech/SpeechModelLocator.swift`
- Create: `Tests/ReadBookAppTests/SpeechModelLocatorTests.swift`

**Interfaces:**
- Consumes: `AppPaths.modelsRoot` and `AppPaths.modelDownloadsRoot`.
- Produces: `SpeechModelDescriptor`, `SpeechModelLocations`, and `SpeechModelLocator.locateAll()`.

- [ ] **Step 1: Write failing locator tests**

```swift
func testReadBookSnapshotWinsOverExternalHuggingFaceCache() throws {
    let fixture = try SpeechModelFixture()
    let owned = try fixture.makeValidSnapshot(for: .tts, root: fixture.readBookRoot)
    _ = try fixture.makeValidSnapshot(for: .tts, root: fixture.externalRoot)
    let locator = SpeechModelLocator(
        ownedRoot: fixture.readBookRoot,
        externalHubRoots: [fixture.externalRoot]
    )
    XCTAssertEqual(try locator.locate(.tts), owned)
}

func testIncompleteOrMissingIndexedShardIsRejected() throws {
    let fixture = try SpeechModelFixture()
    let snapshot = try fixture.makeValidSnapshot(for: .aligner, root: fixture.externalRoot)
    try Data().write(to: snapshot.appendingPathComponent("download.incomplete"))
    XCTAssertNil(try fixture.locator.locate(.aligner))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter SpeechModelLocatorTests`

Expected: FAIL because catalog and locator do not exist.

- [ ] **Step 3: Implement fixed descriptors**

```swift
enum SpeechModelKind: String, CaseIterable, Sendable { case tts, aligner }

struct SpeechModelDescriptor: Equatable, Sendable {
    let kind: SpeechModelKind
    let repoID: String
    let revision: String
    let approximateBytes: Int64
    let requiredRelativePaths: [String]
}

enum SpeechModelCatalog {
    static let tts = SpeechModelDescriptor(
        kind: .tts,
        repoID: "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit",
        revision: "41d3337e8b7f2843a75841595fc14e4b9a7a4b96",
        approximateBytes: 3_080_141_538,
        requiredRelativePaths: [
            "config.json", "generation_config.json", "merges.txt", "model.safetensors",
            "model.safetensors.index.json", "preprocessor_config.json",
            "speech_tokenizer/config.json", "speech_tokenizer/configuration.json",
            "speech_tokenizer/model.safetensors", "speech_tokenizer/preprocessor_config.json",
            "tokenizer_config.json", "vocab.json",
        ]
    )
    static let aligner = SpeechModelDescriptor(
        kind: .aligner,
        repoID: "mlx-community/Qwen3-ForcedAligner-0.6B-4bit",
        revision: "2f652af86ae0c73fe189b9429225c908ce4bf020",
        approximateBytes: 975_854_832,
        requiredRelativePaths: [
            "chat_template.json", "config.json", "generation_config.json", "merges.txt",
            "model.safetensors", "model.safetensors.index.json", "preprocessor_config.json",
            "tokenizer_config.json", "vocab.json",
        ]
    )
}
```

For the aligner use the nine exact files listed by the pinned repository: `chat_template.json`, `config.json`, `generation_config.json`, `merges.txt`, `model.safetensors`, `model.safetensors.index.json`, `preprocessor_config.json`, `tokenizer_config.json`, and `vocab.json`; exclude README and `.gitattributes` from runtime requirements.

- [ ] **Step 4: Implement snapshot validation and cache scanning**

```swift
struct SpeechModelLocator {
    let ownedRoot: URL
    let externalHubRoots: [URL]

    func locate(_ descriptor: SpeechModelDescriptor) throws -> URL? {
        // Check owned revision directory first, then HF models--org--name/snapshots/revision.
        // Reject .incomplete recursively, every missing required path, broken symlinks,
        // and every shard referenced by model.safetensors.index.json that is absent.
    }
}

struct SpeechModelLocations: Equatable, Sendable {
    let tts: URL?
    let aligner: URL?
    var isReady: Bool { tts != nil && aligner != nil }
}
```

Add `func locateAll() throws -> SpeechModelLocations` that calls `locate(.tts)` and `locate(.aligner)` exactly once each. In the test file, define `SpeechModelFixture` as a private helper that creates unique `readBookRoot` and `externalRoot` directories, removes them in `deinit`, and writes every `requiredRelativePaths` entry plus an index JSON whose `weight_map` points to `model.safetensors`.

Add `modelsRoot` and `modelDownloadsRoot` beneath `Application Support/ReadBook` without creating them during `AppPaths.init`.

- [ ] **Step 5: Run tests and verify the current 1.7B snapshot is discovered**

Run: `swift test --filter SpeechModelLocatorTests`

Then add a local diagnostic test invocation that passes `/tmp/readbook-qwen3-tts/hf-home/hub` as an external root and asserts `.tts` is found while `.aligner` reflects its actual presence.

- [ ] **Step 6: Import this machine's validated snapshots into ReadBook-owned storage**

This is a one-time development-machine migration, not a hard-coded product scan path. After Task 1 has downloaded the aligner, resolve each `refs/main`, verify it equals the pinned revision, dereference Hugging Face blob symlinks, and copy into staging before rename:

```bash
prototype_hub=/tmp/readbook-qwen3-tts/hf-home/hub
readbook_models='/Users/sometimes/Library/Application Support/ReadBook/Models'

tts_cache="$prototype_hub/models--mlx-community--Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit"
tts_revision=41d3337e8b7f2843a75841595fc14e4b9a7a4b96
test "$(cat "$tts_cache/refs/main")" = "$tts_revision"
tts_destination="$readbook_models/tts/$tts_revision"
if [[ ! -d "$tts_destination" ]]; then
  mkdir -p "$readbook_models/tts/.partial-$tts_revision"
  rsync -aL "$tts_cache/snapshots/$tts_revision/" "$readbook_models/tts/.partial-$tts_revision/"
  mv "$readbook_models/tts/.partial-$tts_revision" "$tts_destination"
fi

aligner_cache="$prototype_hub/models--mlx-community--Qwen3-ForcedAligner-0.6B-4bit"
aligner_revision=2f652af86ae0c73fe189b9429225c908ce4bf020
test "$(cat "$aligner_cache/refs/main")" = "$aligner_revision"
aligner_destination="$readbook_models/aligner/$aligner_revision"
if [[ ! -d "$aligner_destination" ]]; then
  mkdir -p "$readbook_models/aligner/.partial-$aligner_revision"
  rsync -aL "$aligner_cache/snapshots/$aligner_revision/" "$readbook_models/aligner/.partial-$aligner_revision/"
  mv "$readbook_models/aligner/.partial-$aligner_revision" "$aligner_destination"
fi
```

Run the same `SpeechModelLocator` validation against both destination directories before treating them as installed. Do not remove the source caches in this task.

- [ ] **Step 7: Commit**

```bash
git add Sources/ReadBookCore/Storage/AppPaths.swift Sources/ReadBook/Speech/SpeechModelCatalog.swift Sources/ReadBook/Speech/SpeechModelLocator.swift Tests/ReadBookAppTests/SpeechModelLocatorTests.swift
git commit -m "feat(speech): 扫描并校验本地语音模型"
```

### Task 4: Download only missing model files with resume and atomic install

**Files:**
- Create: `Sources/ReadBook/Speech/SpeechModelDownloader.swift`
- Create: `Sources/ReadBook/Speech/SpeechModelManager.swift`
- Create: `Tests/ReadBookAppTests/SpeechModelDownloaderTests.swift`
- Create: `Tests/ReadBookAppTests/SpeechModelManagerTests.swift`

**Interfaces:**
- Consumes: `SpeechModelDescriptor` and `SpeechModelLocator`.
- Produces: `SpeechModelState`, `SpeechModelManager.prepareMissingModels()`, `cancelDownload()`, and `deleteInstalledModels()`.

- [ ] **Step 1: Write failing downloader tests with an injected transport**

```swift
func testResumeRequestsOnlyRemainingBytesAndAtomicallyInstalls() async throws {
    let transport = RecordingSpeechDownloadTransport(body: Data("def".utf8), total: 6)
    let fixture = try DownloadFixture(partialBytes: Data("abc".utf8))
    let downloader = SpeechModelDownloader(transport: transport, fileManager: .default)
    let installed = try await downloader.download(fixture.descriptor, to: fixture.root) { _ in }
    XCTAssertEqual(await transport.requestedOffsets, [3])
    XCTAssertEqual(try Data(contentsOf: installed.appendingPathComponent("model.safetensors")), Data("abcdef".utf8))
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.partialRoot.path))
}

func testCancellationLeavesPartialFileForResume() async throws {
    let transport = SuspendingSpeechDownloadTransport()
    let fixture = try DownloadFixture(partialBytes: Data())
    let task = Task { try await SpeechModelDownloader(transport: transport).download(fixture.descriptor, to: fixture.root) { _ in } }
    task.cancel()
    do {
        _ = try await task.value
        XCTFail("Expected cancellation")
    } catch is CancellationError {
        // expected
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.partialFile.path))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter SpeechModelDownloaderTests`

Expected: FAIL because downloader interfaces do not exist.

- [ ] **Step 3: Implement Range-based downloading**

```swift
protocol SpeechDownloadTransport: Sendable {
    func contentLength(for url: URL) async throws -> Int64
    func bytes(for url: URL, startingAt offset: Int64) async throws -> AsyncThrowingStream<Data, Error>
}

protocol SpeechModelDownloading: Sendable {
    func download(
        _ descriptor: SpeechModelDescriptor,
        to modelsRoot: URL,
        progress: @Sendable (SpeechDownloadProgress) -> Void
    ) async throws -> URL
}

struct SpeechDownloadProgress: Equatable, Sendable {
    let downloadedBytes: Int64
    let totalBytes: Int64
}

enum SpeechModelState: Equatable, Sendable {
    case notInstalled(missingBytes: Int64)
    case discovering
    case downloading(SpeechDownloadProgress)
    case ready(SpeechModelLocations)
    case failed(String)
}

actor SpeechModelDownloader {
    func download(
        _ descriptor: SpeechModelDescriptor,
        to modelsRoot: URL,
        progress: @Sendable (SpeechDownloadProgress) -> Void
    ) async throws -> URL
}

protocol SpeechPlaybackStopping: Sendable {
    func stopForModelDeletion() async
}

@MainActor
final class SpeechModelManager {
    init(
        locator: SpeechModelLocator,
        downloader: any SpeechModelDownloading,
        stopper: any SpeechPlaybackStopping,
        modelsRoot: URL
    )
}
```

In `SpeechModelDownloaderTests.swift`, define `RecordingSpeechDownloadTransport` as an actor that records the requested start offsets and yields its supplied body once. Define `SuspendingSpeechDownloadTransport` to wait until task cancellation and then throw `CancellationError`. Use explicit `do/catch` so the test introduces no custom asynchronous assertion API:

```swift
do {
    _ = try await task.value
    XCTFail("Expected cancellation")
} catch is CancellationError {
    // expected
}
```

`DownloadFixture` creates a unique root, a one-file descriptor, and the requested partial bytes. `ModelManagerFixture` reuses that root with concrete locator/downloader instances; neither helper reads the user's real model cache.

Construct every URL as `https://huggingface.co/<repo>/resolve/<revision>/<percent-encoded-path>`. Append to `<modelsRoot>/.partial/<kind>/<path>`, verify final content lengths and descriptor-required files, then atomically rename the completed revision directory. Check free capacity before the first byte using `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` and require missing bytes × 1.15.

- [ ] **Step 4: Write failing manager state tests**

```swift
func testExistingTTSOnlyReportsAlignerBytesMissing() async throws {
    let fixture = try ModelManagerFixture(installedKinds: [.tts])
    let manager = SpeechModelManager(
        locator: fixture.locator,
        downloader: fixture.downloader,
        stopper: fixture.stopper,
        modelsRoot: fixture.modelsRoot
    )
    await manager.discover()
    XCTAssertEqual(manager.state, .notInstalled(missingBytes: SpeechModelCatalog.aligner.approximateBytes))
}

func testDeleteStopsBeforeRemovingOwnedModels() async throws {
    let stopper = RecordingSpeechStopper()
    let fixture = try ModelManagerFixture()
    let manager = SpeechModelManager(
        locator: fixture.locator,
        downloader: fixture.downloader,
        stopper: stopper,
        modelsRoot: fixture.modelsRoot
    )
    try await manager.deleteInstalledModels()
    XCTAssertEqual(stopper.stopCount, 1)
}
```

- [ ] **Step 5: Implement manager states and delete behavior**

Make `SpeechModelManager` `@MainActor @Observable`. Discovery must be explicit; its initializer performs no disk or network work. `prepareMissingModels()` downloads only missing descriptors, publishes combined progress, then re-runs locator validation. `deleteInstalledModels()` removes only ReadBook-owned model directories and partials; external HF caches are never removed.

- [ ] **Step 6: Run tests and commit**

Run: `swift test --filter SpeechModelDownloaderTests && swift test --filter SpeechModelManagerTests`

Expected: PASS.

```bash
git add Sources/ReadBook/Speech/SpeechModelDownloader.swift Sources/ReadBook/Speech/SpeechModelManager.swift Tests/ReadBookAppTests/SpeechModelDownloaderTests.swift Tests/ReadBookAppTests/SpeechModelManagerTests.swift
git commit -m "feat(speech): 按需下载并管理语音模型"
```

### Task 5: Implement the generation-safe 10/20/30 sentence queue

**Files:**
- Create: `Sources/ReadBook/Speech/SpeechTypes.swift`
- Create: `Sources/ReadBook/Speech/SpeechQueue.swift`
- Create: `Tests/ReadBookAppTests/SpeechQueueTests.swift`

**Interfaces:**
- Consumes: `SpeechSentence`.
- Produces: `SpeechBlock`, `PreparedSentence`, `PreparedSpeechBlock`, `SpeechGenerationID`, and `SpeechQueue` actor.

- [ ] **Step 1: Write failing queue tests**

```swift
func testQueueRefillsAtTenTargetsTwentyAndNeverExceedsThirty() async {
    let queue = SpeechQueue(lowWatermark: 10, targetCount: 20, hardLimit: 30)
    let id = await queue.restart()
    await queue.append(makePreparedSentences(10), generation: id)
    XCTAssertTrue(await queue.needsRefill)
    XCTAssertEqual(await queue.requestedCapacity, 10)
    await queue.append(makePreparedSentences(25), generation: id)
    XCTAssertEqual(await queue.count, 30)
    XCTAssertFalse(await queue.needsRefill)
}

func testOldGenerationResultsAreDiscardedAfterJump() async {
    let queue = SpeechQueue()
    let old = await queue.restart()
    let current = await queue.restart()
    await queue.append(makePreparedSentences(5), generation: old)
    XCTAssertEqual(await queue.count, 0)
    await queue.append(makePreparedSentences(5), generation: current)
    XCTAssertEqual(await queue.count, 5)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter SpeechQueueTests`

Expected: FAIL because queue types do not exist.

- [ ] **Step 3: Implement value types and queue actor**

```swift
struct PreparedSentence: Equatable, Sendable {
    let sentence: SpeechSentence
    let samples: [Float]
    let sampleRate: Int
}

struct SpeechBlock: Equatable, Sendable {
    let text: String
    let sentences: [SpeechSentence]
    let utf16Range: Range<Int>
}

struct PreparedSpeechBlock: Equatable, Sendable {
    let sentences: [PreparedSentence]
}

struct SpeechGenerationID: Hashable, Sendable { let rawValue: UInt64 }

actor SpeechQueue {
    let lowWatermark: Int
    let targetCount: Int
    let hardLimit: Int
    private var generation: UInt64 = 0
    private var pending: [PreparedSentence] = []

    func restart() -> SpeechGenerationID
    func append(_ sentences: [PreparedSentence], generation: SpeechGenerationID)
    func popFirst() -> PreparedSentence?
    var needsRefill: Bool { get }
    var requestedCapacity: Int { get }
}
```

In `SpeechQueueTests.swift`, define `makePreparedSentences(_ count: Int) -> [PreparedSentence]` with one silent sample per sentence, sample rate 24,000, and non-overlapping one-unit UTF-16 ranges. This keeps queue tests independent from MLX and AVFoundation.

Clamp appends to `hardLimit`; `restart()` increments generation and clears pending. Paused state is not stored here—`AudiobookController` decides whether to request a refill.

- [ ] **Step 4: Run tests and commit**

Run: `swift test --filter SpeechQueueTests`

Expected: PASS.

```bash
git add Sources/ReadBook/Speech/SpeechTypes.swift Sources/ReadBook/Speech/SpeechQueue.swift Tests/ReadBookAppTests/SpeechQueueTests.swift
git commit -m "feat(speech): 增加听书句子缓冲队列"
```

### Task 6: Generate Serena audio and map forced alignment to sentence frames

**Files:**
- Create: `Sources/ReadBook/Speech/SentenceTimingMapper.swift`
- Create: `Sources/ReadBook/Speech/MLXSpeechPipeline.swift`
- Create: `Tests/ReadBookAppTests/SentenceTimingMapperTests.swift`

**Interfaces:**
- Consumes: validated local TTS and aligner directories, `SpeechBlock` and `SpeechSentence`.
- Produces: protocol `SpeechPreparing.prepare(_ block:generation:) async throws -> PreparedSpeechBlock` and actor `MLXSpeechPipeline`.

- [ ] **Step 1: Write failing mapper tests**

```swift
func testChineseCharacterAlignmentMergesIntoSentenceFrameRanges() throws {
    let text = "你不来了？电话里传来吼声。"
    let sentences = SentenceSegmenter().sentences(in: text, startingAt: 0, policy: .exactOffset, limit: 20)
    let items = [
        TimedText(text: "你", start: 0.0, end: 0.2),
        TimedText(text: "不", start: 0.2, end: 0.4),
        TimedText(text: "来", start: 0.4, end: 0.6),
        TimedText(text: "了", start: 0.6, end: 0.8),
        TimedText(text: "电", start: 1.0, end: 1.2),
        TimedText(text: "话", start: 1.2, end: 1.4),
        TimedText(text: "里", start: 1.4, end: 1.6),
        TimedText(text: "传", start: 1.6, end: 1.8),
        TimedText(text: "来", start: 1.8, end: 2.0),
        TimedText(text: "吼", start: 2.0, end: 2.2),
        TimedText(text: "声", start: 2.2, end: 2.4),
    ]
    let result = try SentenceTimingMapper(sampleRate: 24_000).map(items, transcript: text, sentences: sentences)
    XCTAssertEqual(result.first?.frameRange.lowerBound, 0)
    XCTAssertEqual(result.first?.frameRange.upperBound, 19_200)
    XCTAssertGreaterThan(result[1].frameRange.lowerBound, result[0].frameRange.upperBound)
}
```

The test above maps every spoken CJK character; punctuation is skipped but remains inside the sentence UTF-16 range.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter SentenceTimingMapperTests`

Expected: FAIL because mapper does not exist.

- [ ] **Step 3: Implement deterministic alignment mapping**

Normalize only for matching: retain letters/numbers/CJK, lowercase Latin, discard punctuation and whitespace. Walk transcript UTF-16 ranges and aligned items monotonically; do not fuzzy-reorder tokens. The first aligned token in a sentence sets the start frame, the last sets the end frame. Throw `SpeechAlignmentError.unmappedSentence(range)` if any spoken sentence gets no token.

```swift
struct TimedText: Equatable, Sendable { let text: String; let start: Double; let end: Double }
struct AlignedSentence: Equatable, Sendable { let sentence: SpeechSentence; let frameRange: Range<Int64> }
```

- [ ] **Step 4: Implement the native MLX pipeline**

```swift
protocol SpeechPreparing: Sendable {
    func prepare(_ block: SpeechBlock, generation: SpeechGenerationID) async throws -> PreparedSpeechBlock
}

actor MLXSpeechPipeline: SpeechPreparing {
    static let serenaPrompt = "Serena, 使用清澈、干净、少气声、不沙哑的年轻女声，像专业有声书主播一样朗读。对白情绪自然，旁白克制沉浸，吐字清晰，停顿合理。"

    func prepare(_ block: SpeechBlock, generation: SpeechGenerationID) async throws -> PreparedSpeechBlock {
        let tts = try await loadTTSFromValidatedDirectory()
        let audio = try await tts.generate(text: block.text, voice: Self.serenaPrompt, refAudio: nil, refText: nil, language: "Chinese")
        let aligner = try await loadAlignerFromValidatedDirectory()
        let aligned = aligner.generate(audio: audio, text: block.text, language: "Chinese")
        return try splitPCM(audio.asArray(Float.self), using: aligned.items, block: block)
    }
}
```

Keep model objects lazy and reuse them; serialize MLX calls through this actor. If alignment mapping throws, expose `prepareSentenceFallback(_:)` that generates each sentence separately and assigns its entire PCM to that sentence—never estimate timing by character count.

- [ ] **Step 5: Run mapper and opt-in model tests**

Run: `swift test --filter SentenceTimingMapperTests`

Then, with model environment variables still set: `swift test --filter SpeechModelCompatibilityTests`.

Expected: both PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ReadBook/Speech/SentenceTimingMapper.swift Sources/ReadBook/Speech/MLXSpeechPipeline.swift Tests/ReadBookAppTests/SentenceTimingMapperTests.swift
git commit -m "feat(speech): 生成并对齐 Serena 朗读音频"
```

### Task 7: Play bounded PCM with pitch-preserving rate changes

**Files:**
- Create: `Sources/ReadBook/Speech/SpeechPlaybackController.swift`
- Create: `Tests/ReadBookAppTests/SpeechPlaybackControllerTests.swift`

**Interfaces:**
- Consumes: `PreparedSentence` and persisted rate.
- Produces: `SpeechPlaybackState`, `currentSentenceRange`, `enqueue(_:)`, `play()`, `pause()`, `stop()`, and `setRate(_:)`.

- [ ] **Step 1: Write failing pure timeline tests**

```swift
func testRateClampsWithoutChangingSourceFrameSentenceBoundaries() {
    let timeline = SpeechPlaybackTimeline(sentences: [
        .init(range: 0..<10, sourceFrames: 0..<24_000),
        .init(range: 10..<20, sourceFrames: 24_000..<48_000),
    ])
    XCTAssertEqual(timeline.sentence(atSourceFrame: 30_000)?.range, 10..<20)
    XCTAssertEqual(SpeechPlaybackRate.clamp(2.0), 1.5)
    XCTAssertEqual(SpeechPlaybackRate.clamp(0.1), 0.5)
}

func testPauseAndResumeKeepSourceFrame() async {
    let driver = FakeAudioPlaybackDriver()
    let controller = SpeechPlaybackController(driver: driver)
    await controller.enqueue(makePreparedSentence(frames: 48_000))
    await controller.play()
    driver.sourceFrame = 12_000
    await controller.pause()
    await controller.play()
    XCTAssertEqual(driver.lastScheduledStartFrame, 12_000)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter SpeechPlaybackControllerTests`

Expected: FAIL because timeline/controller do not exist.

- [ ] **Step 3: Implement an injectable audio driver and pure timeline**

```swift
protocol AudioPlaybackDriving: AnyObject {
    var sourceFrame: AVAudioFramePosition { get }
    func schedule(samples: [Float], sampleRate: Int, startingAt frame: AVAudioFramePosition)
    func play()
    func pause()
    func stop()
    func setRate(_ rate: Float)
}

enum SpeechPlaybackState: Equatable, Sendable {
    case idle, preparing, playing, paused, buffering
    case failed(String)
}

enum SpeechPlaybackRate {
    static func clamp(_ value: Double) -> Double { min(max(value, 0.5), 1.5) }
}

struct SentencePlaybackTimeline {
    struct Entry: Equatable { let range: Range<Int>; let sourceFrames: Range<Int64> }
    let sentences: [Entry]
    func sentence(atSourceFrame frame: Int64) -> Entry? {
        sentences.first { $0.sourceFrames.contains(frame) }
    }
}
```

In the test file, `FakeAudioPlaybackDriver` stores `sourceFrame`, `lastScheduledStartFrame`, and the last rate; all driver methods only mutate those values. `makePreparedSentence(frames:)` returns 24 kHz silence with a matching UTF-16 range, so tests never start the real audio device.

The production driver owns `AVAudioEngine`, `AVAudioPlayerNode`, and `AVAudioUnitTimePitch`; use a mono Float32 `AVAudioFormat` at each sentence sample rate. Derive highlight from source sample time returned by `playerTime(forNodeTime:)`, not elapsed wall-clock time.

- [ ] **Step 4: Implement controller state transitions**

`idle → preparing → playing`, `playing → paused`, queue starvation to `buffering`, and `stop()` to `idle`. Publish state and range on `@MainActor`; run audio callbacks through a serial queue and hop to the main actor only for observable changes.

- [ ] **Step 5: Run tests and commit**

Run: `swift test --filter SpeechPlaybackControllerTests`

Expected: PASS.

```bash
git add Sources/ReadBook/Speech/SpeechPlaybackController.swift Tests/ReadBookAppTests/SpeechPlaybackControllerTests.swift
git commit -m "feat(speech): 增加倍速听书播放器"
```

### Task 8: Orchestrate start, refill, jump, pause, and position updates

**Files:**
- Create: `Sources/ReadBook/Speech/AudiobookController.swift`
- Create: `Tests/ReadBookAppTests/AudiobookControllerTests.swift`
- Modify: `Sources/ReadBook/App/AppModel.swift`

**Interfaces:**
- Consumes: segmenter, model manager, pipeline, queue, playback, book text and AppModel position callback.
- Produces: `startFromReadingPosition()`, `startFromSelection(_:)`, `togglePlayback()`, `setRate(_:)`, `stop(reason:)`, current sentence range and download presentation state.

- [ ] **Step 1: Write failing orchestration tests**

```swift
func testSelectionStartsAtFirstSelectedUTF16CharacterAndClearsOldGeneration() async throws {
    let fixture = AudiobookFixture(text: "迟到那么久不说，你现在才告诉我？下一句。")
    let selected = (fixture.text as NSString).range(of: "现在")
    await fixture.controller.startFromSelection(selected)
    XCTAssertEqual(fixture.preparer.blocks.first?.sentences.first?.text, "现在才告诉我？")
    XCTAssertEqual(await fixture.queue.currentGeneration, fixture.preparer.generations.last)
}

func testRefillStartsAtTenTargetsTwentyAndStopsAtThirty() async throws {
    let fixture = AudiobookFixture(sentenceCount: 100)
    await fixture.controller.startFromReadingPosition()
    await fixture.consumeUntilQueueCount(10)
    XCTAssertTrue(fixture.preparer.prepareCallCount > 1)
    XCTAssertTrue((10...30).contains(await fixture.queue.count))
}

func testCurrentSentenceWritesCanonicalPosition() async {
    let fixture = AudiobookFixture(sentenceCount: 3)
    fixture.playback.emitCurrentRange(25..<40)
    XCTAssertEqual(fixture.recordedPositions.last, BookPosition(utf16Offset: 25))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter AudiobookControllerTests`

Expected: FAIL because controller does not exist.

- [ ] **Step 3: Implement block building and refill loop**

Build the first sentence alone, then group subsequent complete sentences by paragraph with 2–5 sentences per block. Refill only when playing/buffering and queue count is at or below 10; request enough source sentences to reach 20, never enqueue past 30. Check generation ID after every `await`.

```swift
@MainActor @Observable
final class AudiobookController {
    private(set) var state: SpeechPlaybackState = .idle
    private(set) var highlightedRange: Range<Int>?
    private(set) var queuedSentenceCount = 0

    func startFromReadingPosition(text: String, position: BookPosition) async
    func startFromSelection(text: String, range: NSRange) async
    func togglePlayback() async
    func setRate(_ value: Double)
    func stop(reason: SpeechStopReason) async
}

enum SpeechStopReason: Equatable, Sendable {
    case user, selectionJump, bookChanged, bookRemoved, modelDeleted, applicationTermination
}
```

`AudiobookFixture` in the test file uses a recording `SpeechPreparing`, the real `SpeechQueue`, a fake playback controller conforming to the same playback protocol, and a closure that appends `BookPosition` values. Its `sentenceCount` initializer builds `第1句。第2句。…`; `consumeUntilQueueCount(_:)` repeatedly emits sentence-completion callbacks without sleeping.

- [ ] **Step 4: Wire controller ownership into AppModel**

Inject the controller through `AppModel.init` for tests. `open`, `jump`, `remove` and switching the current book must await or schedule `audiobook.stop(reason:)` before mutating the session. Do not perform model discovery from `AppModel.start()`.

- [ ] **Step 5: Run tests and commit**

Run: `swift test --filter AudiobookControllerTests && swift test --filter ReaderSessionTests`

Expected: PASS.

```bash
git add Sources/ReadBook/Speech/AudiobookController.swift Sources/ReadBook/App/AppModel.swift Tests/ReadBookAppTests/AudiobookControllerTests.swift
git commit -m "feat(speech): 编排听书起播与缓冲补充"
```

### Task 9: Add selection and sentence highlighting to continuous reading

**Files:**
- Create: `Sources/ReadBook/Reader/SpeechSelectionPopover.swift`
- Modify: `Sources/ReadBook/Reader/ContinuousTextView.swift`
- Modify: `Sources/ReadBook/Reader/ContinuousReaderView.swift`
- Modify: `Tests/ReadBookAppTests/ContinuousTextViewTests.swift`

**Interfaces:**
- Consumes: global `highlightedRange: Range<Int>?` and `onStartListeningFromSelection: (NSRange) -> Void`.
- Produces: exact local/global mapping and AppKit selection popover.

- [ ] **Step 1: Write failing coordinator tests**

```swift
func testSelectionMapsFromVirtualWindowToGlobalUTF16Range() {
    let fixture = ContinuousTextFixture(centeredAt: 80_000)
    fixture.textView.setSelectedRange(NSRange(location: 25, length: 4))
    fixture.coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
    XCTAssertEqual(fixture.capturedSelection?.location, fixture.window.utf16Range.lowerBound + 25)
}

func testHighlightAppliesOnlyMappedLocalRange() {
    let fixture = ContinuousTextFixture(centeredAt: 80_000)
    let global = (fixture.window.utf16Range.lowerBound + 40)..<(fixture.window.utf16Range.lowerBound + 46)
    fixture.coordinator.updateHighlight(global)
    XCTAssertNotNil(fixture.textView.textStorage?.attribute(.backgroundColor, at: 42, effectiveRange: nil))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter ContinuousTextViewTests`

Expected: FAIL because selection callback and highlight API do not exist.

- [ ] **Step 3: Implement native selection observation and popover**

Make the coordinator an `NSTextViewDelegate`. On non-empty stable selection, map through `VirtualTextWindow.globalOffset(forLocalOffset:)`, anchor `NSPopover` to `firstRect(forCharacterRange:)`, and expose exactly one button titled “从此处开始听”. Close on selection change, scroll, mode teardown, or hidden window notification.

- [ ] **Step 4: Implement minimal attribute updates**

Track the previous local highlight. Remove `.backgroundColor` only from the old range, add the theme-derived color only to the new mapped range, and call `scrollRangeToVisible` only if the range is outside the visible glyph range. Do not replace the full attributed string for each sentence.

- [ ] **Step 5: Run tests and commit**

Run: `swift test --filter ContinuousTextViewTests`

Expected: PASS, including the existing bounded virtual-window test.

```bash
git add Sources/ReadBook/Reader/SpeechSelectionPopover.swift Sources/ReadBook/Reader/ContinuousTextView.swift Sources/ReadBook/Reader/ContinuousReaderView.swift Tests/ReadBookAppTests/ContinuousTextViewTests.swift
git commit -m "feat(reader): 连续阅读支持听书选区与高亮"
```

### Task 10: Add selection and sentence highlighting to paginated reading

**Files:**
- Modify: `Sources/ReadBook/Reader/PagedTextView.swift`
- Modify: `Sources/ReadBook/Reader/PaginatedReaderView.swift`
- Create: `Tests/ReadBookAppTests/PagedTextViewTests.swift`

**Interfaces:**
- Consumes: current `PageRange`, global highlighted range and the same selection callback as continuous mode.
- Produces: page-local highlight, global selection, and automatic page changes only when the sentence leaves the current page.

- [ ] **Step 1: Write failing page mapping tests**

```swift
func testPageSelectionAddsPageLocationToLocalRange() {
    let mapper = PagedTextRangeMapper(pageRange: PageRange(location: 100, length: 50))
    XCTAssertEqual(mapper.globalRange(for: NSRange(location: 8, length: 4)), NSRange(location: 108, length: 4))
}

func testGlobalHighlightMapsOnlyWhenInsidePage() {
    let mapper = PagedTextRangeMapper(pageRange: PageRange(location: 100, length: 50))
    XCTAssertEqual(mapper.localRange(for: 120..<130), NSRange(location: 20, length: 10))
    XCTAssertNil(mapper.localRange(for: 160..<170))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter PagedTextViewTests`

Expected: FAIL because mapper and selection-enabled view do not exist.

- [ ] **Step 3: Enable native selection and reuse the popover**

Create the range mapper before editing the view:

```swift
struct PagedTextRangeMapper: Equatable {
    let pageRange: PageRange
    func globalRange(for local: NSRange) -> NSRange {
        NSRange(location: pageRange.location + local.location, length: local.length)
    }
    func localRange(for global: Range<Int>) -> NSRange? {
        let page = pageRange.location..<pageRange.upperBound
        guard global.lowerBound >= page.lowerBound, global.upperBound <= page.upperBound else { return nil }
        return NSRange(location: global.lowerBound - page.lowerBound, length: global.count)
    }
}
```

Set `PagedTextView.isSelectable = true`, map selection using `PageRange.location`, and reuse `SpeechSelectionPopover`. Horizontal paging must continue to work when no selection gesture is active.

- [ ] **Step 4: Apply highlight and auto-page only when required**

Pass `highlightedRange` into `PaginatedReaderView`. If it intersects `currentRange`, update only the local background attribute. If it does not, call `PaginationEngine.pageForward` from the sentence start, update `currentRange`, notify position once, then apply the new local highlight. Do not re-page for every sentence already visible.

- [ ] **Step 5: Run tests and commit**

Run: `swift test --filter PagedTextViewTests && swift test --filter PaginationEngineTests && swift test --filter HorizontalPagingGestureTests`

Expected: PASS.

```bash
git add Sources/ReadBook/Reader/PagedTextView.swift Sources/ReadBook/Reader/PaginatedReaderView.swift Tests/ReadBookAppTests/PagedTextViewTests.swift
git commit -m "feat(reader): 分页阅读支持听书选区与高亮"
```

### Task 11: Add toolbar controls, download UI, rate popover, and model settings

**Files:**
- Create: `Sources/ReadBook/Reader/AudiobookControlsView.swift`
- Create: `Sources/ReadBook/Reader/AudiobookDownloadView.swift`
- Modify: `Sources/ReadBook/Reader/ReaderToolbar.swift`
- Modify: `Sources/ReadBook/Reader/ReaderRootView.swift`
- Modify: `Sources/ReadBook/Settings/SettingsView.swift`
- Create: `Tests/ReadBookAppTests/AudiobookControlsTests.swift`

**Interfaces:**
- Consumes: `AudiobookController`, `SpeechModelManager`, preferences, current text/position and text-view callbacks.
- Produces: complete user-visible entry, download, playback, speed and delete flows.

- [ ] **Step 1: Write failing state-to-copy/icon tests**

```swift
func testAudiobookButtonPresentation() {
    XCTAssertEqual(AudiobookButtonPresentation(state: .idle).icon, "headphones")
    XCTAssertEqual(AudiobookButtonPresentation(state: .playing).icon, "pause.fill")
    XCTAssertEqual(AudiobookButtonPresentation(state: .paused).icon, "play.fill")
    XCTAssertEqual(AudiobookButtonPresentation(state: .buffering).help, "正在准备后续内容")
}

func testDownloadCopyUsesOnlyMissingBytes() {
    let presentation = AudiobookDownloadPresentation(missingBytes: 971_305_827)
    XCTAssertTrue(presentation.message.contains("约 0.9 GB"))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter AudiobookControlsTests`

Expected: FAIL because presentations do not exist.

- [ ] **Step 3: Implement toolbar and rate popover**

Define the presentation values as pure types before writing SwiftUI:

```swift
struct AudiobookButtonPresentation: Equatable {
    let icon: String
    let help: String
    init(state: SpeechPlaybackState) {
        switch state {
        case .idle: (icon, help) = ("headphones", "开始听书")
        case .playing: (icon, help) = ("pause.fill", "暂停听书")
        case .paused: (icon, help) = ("play.fill", "继续听书")
        case .preparing: (icon, help) = ("hourglass", "正在准备听书")
        case .buffering: (icon, help) = ("hourglass", "正在准备后续内容")
        case .failed: (icon, help) = ("exclamationmark.triangle", "听书出现错误")
        }
    }
}

struct AudiobookDownloadPresentation: Equatable {
    let missingBytes: Int64
    var message: String { ByteCountFormatter.string(fromByteCount: missingBytes, countStyle: .file) }
}
```

Add one 30 × 30 pt icon beside reading-mode control. Reuse `ToolbarIconLabel`; do not add a second header. `AudiobookControlsView` displays `1.0×` and a slider bound to `0.5...1.5` step `0.1`. Changing rate calls both `model.updatePreferences` and `audiobook.setRate`.

- [ ] **Step 4: Implement download confirmation and progress**

The sheet must have “取消” and “下载并开始听书”. Opening the sheet may run local discovery and HEAD size requests, but weight download starts only from the affirmative button. Preserve the requested start offset while downloading and invoke it after state becomes `.ready`.

- [ ] **Step 5: Wire both reading surfaces**

Pass `audiobook.highlightedRange` and selection callbacks through `ReaderRootView.readingSurface`. Starting from toolbar uses `.containingSentence`; starting from a selection uses `.exactOffset` and clears the native selection after capturing its global range.

- [ ] **Step 6: Add model management in Settings**

Show fixed model names, revisions, source links, MIT/Apache-2.0 notices, installed/missing state, disk usage, and “删除听书模型”. Require a confirmation dialog before deletion; delete only ReadBook-owned models and partial downloads.

- [ ] **Step 7: Run tests and commit**

Run: `swift test --filter AudiobookControlsTests && swift test --filter ReaderChromeControllerTests`

Expected: PASS and toolbar hover behavior unchanged.

```bash
git add Sources/ReadBook/Reader Sources/ReadBook/Settings/SettingsView.swift Tests/ReadBookAppTests/AudiobookControlsTests.swift
git commit -m "feat(reader): 增加听书控制与模型下载界面"
```

### Task 12: Integrate lifecycle without breaking stealth window behavior

**Files:**
- Modify: `Sources/ReadBook/App/AppRuntime.swift`
- Modify: `Sources/ReadBook/App/ReadBookApp.swift`
- Modify: `Sources/ReadBook/Window/WindowRegistry.swift`
- Create: `Tests/ReadBookAppTests/AudiobookLifecycleTests.swift`

**Interfaces:**
- Consumes: `AudiobookController.stop(reason:)`.
- Produces: explicit lifecycle rules for hide, switch, delete and termination.

- [ ] **Step 1: Write failing lifecycle tests**

```swift
func testAutomaticReaderHideDoesNotStopAudiobook() {
    let audiobook = RecordingAudiobookLifecycle()
    let runtime = AppRuntime(audiobookLifecycle: audiobook)
    runtime.windowRegistry.hideReader()
    XCTAssertEqual(audiobook.stopReasons, [])
}

func testRuntimeStopStopsAudiobookAndCancelsGeneration() {
    let audiobook = RecordingAudiobookLifecycle()
    let runtime = AppRuntime(audiobookLifecycle: audiobook)
    runtime.stop()
    XCTAssertEqual(audiobook.stopReasons, [.applicationTermination])
}
```

Define `@MainActor protocol AudiobookLifecycleHandling { func stopImmediately(reason: SpeechStopReason) }`; `RecordingAudiobookLifecycle` appends reasons. Inject it into `AppRuntime.init` and use the real `AudiobookController` adapter in production. `AudiobookController.stopImmediately` synchronously stops AVAudioEngine, increments generation/cancels task handles, and clears observable highlight; it must not await MLX deallocation or disk work.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter AudiobookLifecycleTests`

Expected: FAIL because lifecycle injection does not exist.

- [ ] **Step 3: Implement minimal lifecycle wiring**

Window hide notifications close the selection popover but do not stop playback. Runtime termination synchronously stops audio and cancels generation task handles, then allows the existing `.terminateNow` policy to continue; MLX references are released naturally during process exit, and termination must not wait for model cleanup or queue flush.

- [ ] **Step 4: Run lifecycle and window regression tests**

Run:

```bash
swift test --filter AudiobookLifecycleTests
swift test --filter ReaderWindowStateControllerTests
swift test --filter ReaderWindowInteractionTests
swift test --filter V015InteractionRegressionTests
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReadBook/App/AppRuntime.swift Sources/ReadBook/App/ReadBookApp.swift Sources/ReadBook/Window/WindowRegistry.swift Tests/ReadBookAppTests/AudiobookLifecycleTests.swift
git commit -m "feat(speech): 接入听书生命周期管理"
```

### Task 13: Verify the complete feature, package, sign, and document QA

**Files:**
- Create: `docs/qa/2026-09-01-audiobook-listening-checklist.md`
- Create: `ThirdPartyLicenses/MLXAudioSwift/LICENSE`
- Create: `ThirdPartyLicenses/QwenModels/LICENSE`
- Modify: `Scripts/build-app.sh`

**Interfaces:**
- Consumes: complete feature from Tasks 1–12.
- Produces: fresh automated, real-model, packaging, signing, performance and manual evidence.

- [ ] **Step 1: Run the full automated gate**

Run:

```bash
swift test
swift build
```

Expected: 0 failures and build exit 0.

- [ ] **Step 2: Run the real-model local gate**

Run:

```bash
READBOOK_RUN_SPEECH_MODEL_TESTS=1 \
READBOOK_TTS_MODEL_DIR="$TTS_SNAPSHOT" \
READBOOK_ALIGNER_MODEL_DIR="$ALIGNER_SNAPSHOT" \
swift test --filter SpeechModelCompatibilityTests
```

Record TTS load time, first-sentence start time, sustained real-time factor and peak RSS on the M3 Pro 18 GB machine. The test fails if audio or ordered alignment is empty; performance numbers are recorded, not guessed.

- [ ] **Step 3: Build and verify the app bundle**

Before building, copy the exact upstream MIT text from the pinned MLX Audio Swift commit into `ThirdPartyLicenses/MLXAudioSwift/LICENSE`, and the Apache License 2.0 text referenced by both pinned model cards into `ThirdPartyLicenses/QwenModels/LICENSE`. Extend `Scripts/build-app.sh` with:

```bash
mkdir -p "$APP/Contents/Resources/Licenses/MLXAudioSwift" "$APP/Contents/Resources/Licenses/QwenModels"
cp "$ROOT/ThirdPartyLicenses/MLXAudioSwift/LICENSE" "$APP/Contents/Resources/Licenses/MLXAudioSwift/LICENSE"
cp "$ROOT/ThirdPartyLicenses/QwenModels/LICENSE" "$APP/Contents/Resources/Licenses/QwenModels/LICENSE"
```

Run:

```bash
Scripts/build-app.sh
codesign --verify --deep --strict --verbose=4 dist/ReadBook.app
```

Expected: packaging succeeds, signature verification exits 0, and neither model weights nor Python environments appear inside `dist/ReadBook.app`.

Verify with:

```bash
find dist/ReadBook.app -type f \( -name '*.safetensors' -o -name 'python*' \) -print
```

Expected: no output.

- [ ] **Step 4: Complete the manual QA checklist**

The checklist must record PASS/FAIL for:

- Normal reading starts without model scan, network or MLX load.
- Existing local 1.7B is reused; only missing aligner is downloaded.
- Download confirmation, cancellation, resume, no network and insufficient disk.
- Current-position start and exact selected-character start.
- “从此处开始听” in both modes without breaking copy/selection.
- Sentence highlight, auto-scroll, auto-page and mode switching.
- Pause/resume within a sentence and `0.5x / 1.0x / 1.5x` changes.
- Queue stays between 10 and 30 after warm-up, targets 20 on refill, and clears on jump.
- Top reveal/hide, native drag, all edge/corner Resize, scrolling and paging.
- Window auto-hide continues audio; switch book, delete model and terminate stop safely.
- Empty library and existing library.

- [ ] **Step 5: Run final diff and repository checks**

Run:

```bash
git diff --check origin/main...HEAD
git status --short
git log --oneline origin/main..HEAD
```

Expected: no whitespace errors, no unrelated files, and only the planned Chinese commits.

- [ ] **Step 6: Commit QA evidence**

```bash
git add docs/qa/2026-09-01-audiobook-listening-checklist.md ThirdPartyLicenses Scripts/build-app.sh
git commit -m "test(audiobook): 记录听书功能验收结果"
```

- [ ] **Step 7: Stop before remote operations**

Report the branch, commits, changed files, fresh test/build/package/signing results and any failed manual checks. Do not push, open a PR, merge, tag or release without a separate explicit request.
