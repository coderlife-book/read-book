# ReadBook

ReadBook 是一个个人自用的 macOS 原生 TXT 小说阅读器。它不是 WidgetKit 小组件，而是一个外观和使用方式接近桌面 Widget 的轻量 App：窗口很小、界面尽量只保留正文，同时拥有普通 App 才能提供的完整阅读交互。

## V1 能力

- 导入本地 `.txt`，导入后复制到 ReadBook 自己的本地书库
- UTF-8 / UTF-16 / GB18030（兼容常见 GBK）/ Big5 解码
- 自动识别常见中文章节标题并支持目录搜索、跳转
- 多本小说与最近阅读
- 分页阅读：点击左右区域、方向键、触控板横向翻页
- 连续阅读：触控板 / 鼠标上下无限滚动
- 两种模式共享 UTF-16 阅读位置，切换、改字号、改窗口尺寸不会以“页码”作为进度依据
- 苹方 / 宋体 / 楷体 / 系统字体，字号和行距可调
- 柔和 / 明亮 / 深色三种主题
- 窗口位置和尺寸自动恢复
- 始终置顶开关
- 小组件模式（隐藏 Dock）与普通 App 模式（显示 Dock）可切换
- 菜单栏入口
- 阅读位置自动延迟保存，并在切书、隐藏窗口、App inactive/background、退出时强制保存

## 系统要求

- macOS 26+
- Apple Silicon / Intel 均可由 Swift Package 构建；主要使用目标是 Apple Silicon MacBook Pro
- Xcode 26+ / Swift 6

## 开发运行

```bash
swift test
swift run ReadBook
```

打包成本地 `.app`：

```bash
Scripts/build-app.sh
open dist/ReadBook.app
```

项目没有网络层、账号体系或后端，不需要 Supabase。

## 数据位置

导入后的小说保存在：

```text
~/Library/Application Support/ReadBook/
├── library.json
├── Books/
│   └── <UUID>/
│       ├── content.txt
│       └── metadata.json
└── Cache/
```

`content.txt` 在导入阶段统一转换为 UTF-8。每本书的权威阅读位置是 UTF-16 offset，而不是页码。

如果 `library.json` 损坏，会从书籍目录重建索引；如果单本 `metadata.json` 损坏但 `content.txt` 仍存在，会重新扫描正文和章节并生成可继续阅读的恢复元数据。

## 快捷操作

- `⌘O`：导入 TXT
- 分页模式 `← / →`：上一页 / 下一页
- 点击分页窗口左半区域 / 右半区域：上一页 / 下一页
- 连续模式：正常使用触控板、鼠标滚轮、方向键或 Page Up / Page Down

## V1 不做

EPUB、PDF、MOBI、在线抓书、账号、云同步、AI、全文搜索、笔记、划线、TTS、封面管理、iOS、WidgetKit 都不在 V1 范围内。

详细设计与实施计划见 `docs/superpowers/`。
