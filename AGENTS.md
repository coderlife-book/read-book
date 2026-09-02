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

涉及发布流程时，还要运行：

```bash
bash Tests/ReleasePolicyTests.sh
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
   chore(release): 准备 v0.2.1 发布
   ```

4. 推送功能分支并创建指向 `main` 的 PR，禁止直接 push `main`。
5. **PR 默认必须创建为非 Draft（`draft=false`）**。TDD 的 RED 阶段、实现未完成或正在等待 CI，都通过 PR 描述、提交记录和检查状态表达，不得为了表示“未完成”而创建 Draft PR。
6. 只有用户明确要求 Draft PR 时才允许创建 Draft。当前 GitHub 连接器的 `Draft -> Ready for review` mutation 存在 GraphQL 兼容性问题，因此任何自动化流程都不得依赖“先 Draft、完成后再转 Ready”这一步。
7. 等待 PR 的 `test-build-package` 检查成功；失败时先定位、修复并重新验证，不得绕过检查合并，也不需要因为普通 CI/工程失败中断流程等待用户确认。
8. PR 满足既定需求、没有阻塞级 review 问题且 `test-build-package` 成功后，**默认自动 Squash merge 到 `main`，不再额外等待用户逐次授权**；只有确有必要保留多个有意义提交时才使用普通 merge。
9. 合并后自动继续跟踪 `main` 对应的 `macOS CI`。如果本次属于正式发布，继续跟踪直到对应 Release 创建完成，并核对目标 SHA、ZIP、`.sha256` 与 checksum；无需用户再发送“继续”“合并”“发布”等中间确认。
10. 只有遇到以下情况才暂停并请求用户决策：需求存在会显著改变结果的关键歧义；需要覆盖/删除已有 tag 或 Release；需要 force push、改写共享历史或绕过 CI；涉及付费、凭证、外部账号授权或其他明显不可逆/高影响操作。

建议在 GitHub 为 `main` 开启以下分支保护：

- Require a pull request before merging
- Require status checks to pass before merging
- 必选检查：`test-build-package`
- 禁止 force push 和删除分支
- 个人项目可以暂不要求人工 Review，但不得取消 CI 门禁

## 版本与发布门禁

任何会改变用户实际运行 App 的 PR，都必须在同一个 PR 中同步更新版本号和 Build Number，不能先把功能合并进 `main`、再补一个版本 PR。

发布策略采用“维护路径白名单”而不是“产品路径白名单”：只有明确属于维护类的路径可以免升版本，其他路径（包括以后新建的未知目录）默认都视为会影响发布。这样新增 `Resources/`、配置目录或其他产物路径时，不会因为门禁规则没同步更新而漏发版本。

当前明确免升版本的维护路径：

- `.github/**`
- `Tests/**`
- `AGENTS.md`
- `README.md`
- `docs/**`
- `.gitignore`
- `Scripts/check-release-policy.sh`

因此 `Sources/**`、`DesignAssets/**`、`Package.swift`、`Package.resolved`、`Scripts/build-app.sh`、`Scripts/render-branding.swift` 以及任何未明确豁免的新路径都会要求发布新版本。

版本规则：

1. 用户产物变更必须修改 `Scripts/build-app.sh` 中的默认 `APP_VERSION` 和 `APP_BUILD`。
2. `APP_VERSION` 必须相对 PR base 严格递增，使用数字三段式版本，例如 `0.2.0 -> 0.2.1`。
3. `APP_BUILD` 也必须严格递增，例如 `12 -> 13`。
4. 同一个 PR 必须同步更新 workflow 中的 Release Notes，只描述该版本实际包含的用户可见变化。
5. `Scripts/check-release-policy.sh` 是版本门禁的单一实现；`Tests/ReleasePolicyTests.sh` 必须覆盖维护改动、漏升版本、未知路径默认发布、漏升 Build 和合法发布等情况。
6. PR CI 在编译前执行发布门禁；用户产物变更如果没有正确升版本，`test-build-package` 必须直接失败，禁止合并。

## CI 与发布流程

当前 `.github/workflows/bootstrap-readbook.yml` 同时处理 PR 验证和 `main` 发布：

- `pull_request -> main`：执行发布策略检查；需要构建时执行测试、构建、打包、签名与校验，只上传临时 Artifact，不发布 Release。
- `push -> main`：重新执行同一套验证，并重新判断本次提交是否需要发布。
- `.github/**`、`Tests/**` 等维护改动可以完整跑 CI，但 `release_required=false`，不会创建 GitHub Release。
- 只有用户产物变更且 `main` 的 `test-build-package` 成功后，`publish` Job 才运行。
- `publish` 使用 App 内版本号创建不可变的 `v<版本号>` tag 和 GitHub Release。
- 如果本应发布的 `v<版本号>` 已存在，`publish` 必须失败并提示版本冲突；不得再使用 `exit 0` 静默跳过，否则会产生“main 已更新但 Release 仍是旧包”的假成功状态。

这里的两次 CI 不是发布两次：`pull_request -> main` 负责验证候选代码，`push -> main` 才对合并后的提交执行正式打包和发布。文档-only PR（仅修改 `AGENTS.md`、README 或 `docs/`）保留成功的 `test-build-package` 检查但跳过 Swift 测试、编译、打包和签名。代码、测试或 workflow 变更仍完整验证。合并到 `main` 后始终完整构建，但只有 `release_required=true` 才进入正式发布。

Release Notes 的 Bash 兼容性：不要在 `--notes "...\n..."` 中依赖 `\n` 生成换行。Bash 的普通双引号不会解释 `\n`，GitHub 页面会显示字面量 `\n`。应使用 heredoc 写入临时 Markdown 文件，再通过 `gh release create ... --notes-file release-notes.md` 发布。

正式发布流程：

1. 在用户产物变更 PR 中同时更新功能代码、`APP_VERSION`、`APP_BUILD` 和 Release Notes。
2. 运行 `bash Tests/ReleasePolicyTests.sh`，确认版本策略测试通过。
3. 完成本地测试、Release 构建、签名和产物校验。
4. 创建 PR，等待 `test-build-package` 成功；版本未递增时 CI 应在编译前失败。
5. `test-build-package` 成功后默认自动合并；合并后等待 `main` CI 成功，由 `publish` 自动创建新 tag 和 GitHub Release。
6. 自动核验 Release 的目标 SHA、ZIP、`.sha256` 文件以及下载包 SHA-256；确认发布链路完成后再向用户汇报最终结果。

除非用户明确要求，不手动创建或覆盖 tag/Release，也不跳过 workflow 发布；正常的自动发布应始终由 `main` workflow 完成。

## 工作区安全

- 工作区可能包含用户未提交的改动；不要撤销、覆盖或提交无关变更。
- 禁止使用 `git reset --hard`、`git checkout --` 等破坏性命令处理用户改动。
- 用户一旦批准当前开发任务，默认授权在该任务范围内执行：推送任务分支、创建/更新 PR、在 CI 全绿且无阻塞问题后合并 PR，以及跟踪正常的 workflow 自动发布；这些步骤不再逐项请求确认。
- 仍然禁止直接 push `main`、force push、改写共享历史、绕过必选检查，以及覆盖/删除已有 tag 或 Release；这类操作必须单独取得用户确认。
- 完成实现后报告改动文件、验证结果、最终 `main` 状态和 Release 状态，不再把“尚未执行的常规远端操作”留给用户手动确认。
