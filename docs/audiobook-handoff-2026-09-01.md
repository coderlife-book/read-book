# ReadBook 听书功能交接文档

更新时间：2026-09-01（会话二收尾）

## 当前状态

- 工作树：`/tmp/readbook-worktrees/audiobook-design`
- 分支：`codex/audiobook-design`
- 远端：`origin/codex/audiobook-design`
- 当前提交：`9d57eee`
- 工作树状态：干净
- PR：[coderlife-book/read-book#17](https://github.com/coderlife-book/read-book/pull/17)
- CI：[macOS CI #33495319568](https://github.com/coderlife-book/read-book/actions/runs/33495319568)
- CI 结果：最新 head `d671974` 上 `test-build-package` 成功；PR 场景下 `publish` 按设计跳过

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
- 分页模式当前句离开本页时自动以句首重新分页
- 首次下载后保留“从此处开始听”的选区，下载完成自动从选区起播

### 模型策略

- 普通阅读不会扫描、下载或加载模型
- 第一次点击听书时扫描 ReadBook 自有目录和 Hugging Face 缓存
- 已有本地模型直接使用
- 缺失模型才显示下载确认
- 下载支持 partial 和断点续传
- 模型权重不进入 Git、不打进 App
- 设置页展示 TTS/对齐模型的状态、来源链接、revision、许可证和磁盘占用
- 设置页可删除 ReadBook 管理的模型，删除前停止播放并释放控制器
- 下载弹窗按实际缺失容量提示（已有 TTS 时只显示对齐模型体积）

## 验证证据

在当前分支执行过：

```bash
swift test
swift build
git diff --check
```

结果：`swift test` 共 127 个测试，0 失败，4 个显式跳过；`swift build` 成功。

显式跳过的是本地真实模型测试，需要设置 `READBOOK_RUN_SPEECH_MODEL_TESTS=1` 和两个模型目录环境变量。

真实模型测试（显式启用）全部通过：

```text
READBOOK_RUN_SPEECH_MODEL_TESTS=1 READBOOK_TTS_MODEL_DIR=... READBOOK_ALIGNER_MODEL_DIR=... \
  swift test --filter SpeechModelCompatibilityTests
```

覆盖 TTS 生成、ForcedAligner 对齐、以及 Pipeline 整块准备。

本地 Release 包已生成并通过签名校验：

```text
/tmp/readbook-worktrees/audiobook-design/dist/ReadBook.app
```

`codesign --verify --deep --strict --verbose=4 dist/ReadBook.app` 通过；
包内含 `Contents/MacOS/mlx.metallib`（MLX Metal 内核库），不含模型权重。

注意：当前打包脚本生成的是 ad-hoc 签名 App，不包含约 3.8 GB 模型；首次体验需在 App 内按需下载，或确保本机已有固定 revision 的模型快照。

## 当前已知问题 / 未完成项

1. 选区浮层仍是 SwiftUI popover，尚未替换为独立的 `SpeechSelectionPopover` AppKit 组件；功能动作已接通。
2. CI 没有上传 Artifact，PR workflow 只验证构建；正式安装包需要合并到 `main` 后由发布 Job 生成，或本地使用 `dist/ReadBook.app`。
3. 尚未完成真实窗口人工验收：试听、句子高亮随播放移动、暂停/倍速、分页自动跟随、选区浮层定位。

## 新会话建议顺序

1. 先打开本文件和 `docs/superpowers/specs/2026-09-01-audiobook-listening-design.md`、`docs/superpowers/plans/2026-09-01-audiobook-listening.md`。
2. 检查 PR #17 的最新 CI，不要重复创建 PR。
3. 在 macOS 实际窗口中试听用户给出的文本，确认 Serena 声音、去沙感、速度和高亮同步，并验收分页自动翻页与下载进度弹窗。
4. 如需要，把选区浮层替换为原生 AppKit `SpeechSelectionPopover`。
5. 最后执行：

```bash
swift test
swift build
Scripts/build-app.sh
codesign --verify --deep --strict --verbose=4 dist/ReadBook.app
```

除非用户明确要求，不要推送远端、合并 PR、创建 tag 或发布 Release。当前分支比 `origin/codex/audiobook-design` 领先 3 个未推送提交（`935e122`、`812942d`、`9d57eee`）。

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
