# ReadBook 项目协作说明

## 项目定位

ReadBook 是一个个人自用的 macOS 原生 TXT 小说阅读器，目标是像桌面小组件一样轻量、低打扰，但保留普通 macOS App 的完整窗口交互。

- 技术栈：Swift 6、SwiftUI、AppKit、Swift Package Manager
- 系统要求：macOS 26+
- 数据策略：纯本地存储，不接入账号、云同步或 Supabase
- 核心模块：`ReadBookCore` 负责模型、存储、解析、分页与阅读会话；`ReadBook` 负责 App、窗口和界面
- 入口与结构以 `Package.swift`、`Sources/ReadBookCore/`、`Sources/ReadBook/` 为准

## 产品与实现约束

- 保持实现小而直接，只处理当前明确需求，不提前增加扩展层或配置项。
- 窗口只有一条顶部区域；不得同时显示系统 Header 和自定义 Header。
- 顶部工具栏默认隐藏，鼠标进入顶部区域后出现，离开后隐藏。
- 工具按钮需要约 30 x 30 pt 的完整点击热区，并提供浅灰 hover 反馈。
- 窗口拖动和四边、四角 Resize 优先使用 AppKit/macOS 原生行为。
- 不得用覆盖正文的透明 SwiftUI 手势层实现窗口 Resize，以免抢占滚动和文本事件。
- AppKit 窗口圆角、SwiftUI 内容裁切和阴影层级必须保持一致，避免四角出现背景或阴影月牙。
- 两种阅读模式共享 UTF-16 offset 阅读位置；不得把页码作为权威进度。
- 改动必须外科手术化，不顺手重构、格式化或清理无关代码。

## 本地验证

日常代码改动至少运行：

```bash
swift test
swift build
```

涉及窗口、打包、图标、签名或发布时，还要运行：

```bash
Scripts/build-app.sh
codesign --verify --deep --strict --verbose=4 dist/ReadBook.app
```

涉及窗口交互时，需要针对受影响行为做人工验证，包括：

- 顶部显示与隐藏
- 顶部拖动窗口
- 四边和四角 Resize
- 正文滚动、文本事件与翻页不被顶部或 Resize 热区抢占
- 空书库和已有书籍两种状态
- 窗口四角无重复背景、阴影月牙或裁切错层

验证结论必须基于本次改动后的最新命令输出；不能用旧结果或推测代替。

## Git 与 PR 流程

`main` 是稳定分支，协作时必须按受保护分支对待。任何功能、修复、文档或发布准备都必须通过 PR 进入 `main`。

1. 从最新 `main` 创建分支，分支名使用 `codex/<简短主题>`。
2. 只提交与当前任务直接相关的文件。
3. 提交信息使用 `type(scope): 中文描述`，例如：

   ```text
   fix(window): 修复顶部拖动区域事件
   feat(reader): 增加连续滚动模式
   chore(release): 准备 v0.2.0 发布
   ```

4. 推送功能分支并创建指向 `main` 的 PR，禁止直接 push `main`。
5. 等待 PR 的 `test-build-package` 检查成功；失败时先修复并重新验证，不得绕过检查合并。
6. PR 通过后再合并到 `main`，优先使用 Squash merge；需要保留多个有意义提交时才使用普通 merge。
7. 合并后确认 `main` 对应的 `macOS CI` 再次成功。

建议在 GitHub 为 `main` 开启以下分支保护：

- Require a pull request before merging
- Require status checks to pass before merging
- 必选检查：`test-build-package`
- 禁止 force push 和删除分支
- 个人项目可以暂不要求人工 Review，但不得取消 CI 门禁

## CI 与发布流程

当前 `.github/workflows/bootstrap-readbook.yml` 同时处理 PR 验证和 `main` 发布：

- `pull_request -> main`：执行测试、构建、打包、签名与校验，只上传临时 Artifact，不发布 Release。
- `push -> main`：重新执行同一套验证。
- 只有 `main` 的 `test-build-package` 成功后，`publish` Job 才能运行。
- `publish` 使用 App 内版本号创建不可变的 `v<版本号>` tag 和 GitHub Release；已有 tag 不覆盖。

这里的两次 CI 不是发布两次：`pull_request -> main` 只验证候选代码并上传临时 Artifact，`push -> main` 才对合并后的提交执行正式打包和发布。两次构建是为了确保正式产物来自最终的 `main` 提交。

Release Notes 的 Bash 兼容性：不要在 `--notes "...\n..."` 中依赖 `\n` 生成换行。Bash 的普通双引号不会解释 `\n`，GitHub 页面会显示字面量 `\n`。应使用 heredoc 写入临时 Markdown 文件，再通过 `gh release create ... --notes-file release-notes.md` 发布。

普通功能 PR：

- 不修改 `Scripts/build-app.sh` 中的版本号和 Build Number。
- 合并后因为对应版本 Release 已存在，workflow 不会覆盖历史产物。

正式 Release PR：

1. 确认待发布功能和修复已经进入发布分支，或将版本准备与最终改动放在同一个 PR 中验证。
2. 更新 `Scripts/build-app.sh` 的 `APP_VERSION` 和 `APP_BUILD`；两者都必须递增。
3. 更新 workflow 中对应版本的 Release Notes，内容只描述本次发布。
4. 本地完成测试、Release 构建、签名和产物校验。
5. 创建 Release PR，等待 PR CI 成功后合并。
6. 合并后等待 `main` CI 成功，由 `publish` 自动创建 tag 和 GitHub Release。
7. 最终核验 Release 的目标 SHA、ZIP、`.sha256` 文件以及下载包 SHA-256。

除非用户明确要求，不手动创建 tag、覆盖 Release 或跳过 workflow 发布。

## 工作区安全

- 工作区可能包含用户未提交的改动；不要撤销、覆盖或提交无关变更。
- 禁止使用 `git reset --hard`、`git checkout --` 等破坏性命令处理用户改动。
- 未经用户明确要求，不向远端推送、不合并 PR、不创建 tag 或发布 Release。
- 完成实现后报告改动文件、验证结果、当前分支，以及尚未执行的远端操作。
