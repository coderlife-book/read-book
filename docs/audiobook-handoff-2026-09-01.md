# ReadBook 听书功能交接文档

更新时间：2026-09-01

## 当前状态

- 工作树：`/tmp/readbook-worktrees/audiobook-design`
- 分支：`codex/audiobook-design`
- 远端：`origin/codex/audiobook-design`
- 当前提交：`cfd5a48`
- 工作树状态：干净
- PR：[coderlife-book/read-book#17](https://github.com/coderlife-book/read-book/pull/17)
- CI：[macOS CI #33494592320](https://github.com/coderlife-book/read-book/actions/runs/33494592320)
- CI 结果：`test-build-package` 成功；PR 场景下 `publish` 按设计跳过

## 已完成

### 本地语音链路

- 固定 TTS：`mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit`
- TTS revision：`41d3337e8b7f2843a75841595fc14e4b9a7a4b96`
- 固定对齐模型：`mlx-community/Qwen3-ForcedAligner-0.6B-4bit`
- 对齐 revision：`2f652af86ae0c73fe189b9429225c908ce4bf020`
- 固定声线：Serena
- 固定指令：清澈、干净、少气声、不沙哑，专业有声书主播风格
- 原生依赖锁定在 `mlx-audio-swift` revision `3506fb93cc3b9e4a642079d5384eaca0373962e6`

### 播放与阅读

- UTF-16 分句和全局范围映射
- 当前句背景高亮
- 连续阅读、分页阅读均支持选区映射
- 选区浮层动作：`从此处开始听`
- 工具栏听书按钮
- 倍速范围 `0.5x...1.5x`，步长 `0.1x`，持久化到阅读偏好
- 暂停后从播放器源采样帧继续
- 句子播放完成自动推进
- 队列低水位 10、目标 20、硬上限 30
- 换书、删除当前书、退出 App 时停止听书任务

### 模型策略

- 普通阅读不会扫描、下载或加载模型
- 第一次点击听书时扫描 ReadBook 自有目录和 Hugging Face 缓存
- 已有本地模型直接使用
- 缺失模型才显示下载确认
- 下载支持 partial 和断点续传
- 模型权重不进入 Git、不打进 App

## 验证证据

在当前分支执行过：

```bash
swift test
swift build
git diff --check
```

结果：`swift test` 共 112 个测试，0 失败，4 个显式跳过；`swift build` 成功。

显式跳过的是本地真实模型测试，需要设置 `READBOOK_RUN_SPEECH_MODEL_TESTS=1` 和两个模型目录环境变量。

本地 Release 包已生成：

```text
/tmp/readbook-worktrees/audiobook-design/dist/ReadBook.app
```

注意：当前打包脚本生成的是 ad-hoc 签名 App，不包含约 3.8 GB 模型；首次体验需在 App 内按需下载，或确保本机已有固定 revision 的模型快照。

## 当前已知问题 / 未完成项

1. 设置页尚未加入完整的“模型状态、来源、revision、许可证、删除模型”界面。
2. 选区浮层目前已接入功能动作，但还没有独立的 `SpeechSelectionPopover` AppKit 组件；当前实现是 SwiftUI popover。
3. 首次下载后从选区起播的“保存选区、下载完成后恢复原选区”流程还需要补完整；已有模型时精确选区起播正常。
4. 默认 `AppModel` 使用惰性 `AudiobookController`，目前没有把模型管理器独立注入到 AppModel 测试夹具中。
5. `PagedTextView` 的通知闭包仍有 Swift 6 AppKit actor warning，需要后续清理为显式 `Task { @MainActor in ... }`。
6. CI 没有上传 Artifact，PR workflow 只验证构建；正式安装包需要合并到 `main` 后由发布 Job 生成，或本地使用 `dist/ReadBook.app`。
7. 尚未完成真实窗口人工验收：试听、句子高亮随播放移动、暂停/倍速、分页自动跟随、选区浮层定位。

## 新会话建议顺序

1. 先打开本文件和 `docs/superpowers/specs/2026-09-01-audiobook-listening-design.md`、`docs/superpowers/plans/2026-09-01-audiobook-listening.md`。
2. 检查 PR #17 的最新 CI，不要重复创建 PR。
3. 先修正真实模型打包/运行所需的 `mlx.metallib` 复制问题，并用本机模型执行真实 Pipeline 测试。
4. 完成设置页模型管理和删除流程测试。
5. 补选区下载后恢复、分页高亮自动翻页、AppModel 生命周期测试。
6. 在 macOS 实际窗口中试听用户给出的文本，确认 Serena 声音、去沙感、速度和高亮同步。
7. 最后执行：

```bash
swift test
swift build
Scripts/build-app.sh
codesign --verify --deep --strict --verbose=4 dist/ReadBook.app
```

除非用户明确要求，不要推送 `main`、合并 PR、创建 tag 或发布 Release。

## 重要实现文件

- `Sources/ReadBook/Speech/MLXSpeechPipeline.swift`
- `Sources/ReadBook/Speech/SpeechPlaybackController.swift`
- `Sources/ReadBook/Speech/AudiobookController.swift`
- `Sources/ReadBook/Speech/SpeechModelLocator.swift`
- `Sources/ReadBook/Speech/SpeechModelDownloader.swift`
- `Sources/ReadBook/Reader/ContinuousTextView.swift`
- `Sources/ReadBook/Reader/PagedTextView.swift`
- `Sources/ReadBook/Reader/ReaderRootView.swift`
- `Sources/ReadBook/App/AppModel.swift`

## 模型本机路径

当前开发机已存在固定模型，路径为：

```text
/Users/sometimes/Library/Application Support/ReadBook/Models/tts/41d3337e8b7f2843a75841595fc14e4b9a7a4b96
/Users/sometimes/Library/Application Support/ReadBook/Models/aligner/2f652af86ae0c73fe189b9429225c908ce4bf020
```

不要把这些模型目录复制进仓库或提交到 Git。
