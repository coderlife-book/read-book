import AppKit
import ReadBookCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var model: AppModel
    let runtime: AppRuntime

    private let fonts = ["PingFang SC", "Songti SC", "STKaiti", "System"]
    @State private var isDeleteModelConfirmationPresented = false
    @State private var isModelImportPresented = false
    @State private var modelImportKind: SpeechModelKind = .tts
    @State private var localModelManagementError: String?
    @AppStorage("speechModelDownloadSourceMode") private var downloadSourceModeRaw = SpeechModelDownloadSourceMode.huggingFace.rawValue
    @AppStorage("speechModelCustomMirrorURL") private var customMirrorURL = ""

    var body: some View {
        Form {
            Section("排版") {
                Picker("字体", selection: binding(\.fontFamily)) {
                    ForEach(fonts, id: \.self) { Text(fontDisplayName($0)).tag($0) }
                }

                LabeledContent("字号") {
                    HStack {
                        Slider(value: binding(\.fontSize), in: 12...30, step: 1)
                        Text("\(Int(model.preferences.fontSize))")
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                }

                LabeledContent("行间距") {
                    HStack {
                        Slider(value: binding(\.lineSpacing), in: 0...16, step: 1)
                        Text("\(Int(model.preferences.lineSpacing))")
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                }

                LabeledContent("正文颜色") {
                    HStack(spacing: 10) {
                        ColorPicker("正文颜色", selection: textColorBinding, supportsOpacity: false)
                            .labelsHidden()
                        Button("跟随主题") {
                            model.updatePreferences { $0.textColorHex = nil }
                        }
                        .disabled(model.preferences.textColorHex == nil)
                    }
                }
            }

            Section("外观") {
                Picker("主题", selection: binding(\.theme)) {
                    Text("柔和").tag(ReaderTheme.soft)
                    Text("明亮").tag(ReaderTheme.light)
                    Text("深色").tag(ReaderTheme.dark)
                }
                .pickerStyle(.segmented)

                Picker("窗口外观", selection: Binding(
                    get: { model.preferences.windowAppearance },
                    set: { value in
                        model.updatePreferences { $0.windowAppearance = value }
                        runtime.applyPreferences(model.preferences)
                    }
                )) {
                    Text("卡片").tag(ReaderWindowAppearance.card)
                    Text("无边框").tag(ReaderWindowAppearance.frameless)
                    Text("纯透明").tag(ReaderWindowAppearance.transparent)
                }
                .pickerStyle(.segmented)

                if model.preferences.windowAppearance == .frameless {
                    LabeledContent("底色") {
                        HStack {
                            Slider(value: Binding(
                                get: { model.preferences.framelessBackgroundOpacity },
                                set: { value in
                                    model.updatePreferences { $0.framelessBackgroundOpacity = value }
                                }
                            ), in: 0...0.60, step: 0.01)
                            Text("\(Int(model.preferences.framelessBackgroundOpacity * 100))%")
                                .monospacedDigit()
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
            }

            Section("老板模式") {
                Toggle("启用老板模式", isOn: Binding(
                    get: { model.preferences.bossModeEnabled },
                    set: { value in
                        model.updatePreferences { preferences in
                            preferences.bossModeEnabled = value
                            if value, preferences.windowAppearance == .card {
                                preferences.windowAppearance = .transparent
                            }
                        }
                        runtime.applyPreferences(model.preferences)
                    }
                ))

                Picker("行为", selection: Binding(
                    get: { model.preferences.bossModeProfile },
                    set: { value in runtime.setBossProfile(value, using: model) }
                )) {
                    Text("悬浮阅读").tag(BossModeProfile.floatingReading)
                    Text("隐蔽").tag(BossModeProfile.concealed)
                }

                Toggle("锁定为可交互（本次运行）", isOn: Binding(
                    get: { runtime.windowState.lockInteractive },
                    set: { runtime.setLockInteractive($0) }
                ))

                Text("安全模式已启用：ReadBook 不注册全局键盘快捷键、不监听 Option，也不监听系统级鼠标移动。显示/隐藏与恢复交互请使用菜单栏。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("正文区域悬停和滚动不会唤出标题栏或章节栏。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("窗口") {
                Toggle("始终置顶", isOn: Binding(
                    get: { model.preferences.alwaysOnTop },
                    set: { value in
                        model.updatePreferences { $0.alwaysOnTop = value }
                        runtime.applyPreferences(model.preferences)
                    }
                ))

                Picker("应用模式", selection: Binding(
                    get: { model.preferences.appPresenceMode },
                    set: { value in
                        model.updatePreferences { $0.appPresenceMode = value }
                        runtime.applyPreferences(model.preferences)
                    }
                )) {
                    Text("小组件模式（隐藏 Dock）").tag(AppPresenceMode.widgetStyle)
                    Text("普通 App（显示 Dock）").tag(AppPresenceMode.normal)
                }
            }

            Section("更新") {
                LabeledContent("当前版本") {
                    Text(currentVersion)
                        .monospacedDigit()
                }
                Button("检查更新…") {
                    runtime.showReader()
                    Task { await runtime.updater.check(manual: true) }
                }
                Text("ReadBook 会在启动后自动检查一次新版本；发现更新后由你确认才会下载和安装。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("听书") {
                Picker("下载源", selection: $downloadSourceModeRaw) {
                    Text("Hugging Face").tag(SpeechModelDownloadSourceMode.huggingFace.rawValue)
                    Text("自定义 HF 镜像").tag(SpeechModelDownloadSourceMode.customMirror.rawValue)
                }

                if downloadSourceMode == .customMirror {
                    TextField("例如 https://hf-mirror.com", text: $customMirrorURL)
                        .textFieldStyle(.roundedBorder)
                    Text("镜像需要兼容 Hugging Face 的 /repo/resolve/revision/file 下载路径。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(model.audiobookModelRows, id: \.kind) { row in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(row.name)
                            Spacer()
                            modelStatusBadge(row)
                        }
                        Link(row.repoID, destination: row.sourceURL)
                            .font(.caption)
                        HStack(spacing: 8) {
                            Text("Revision \(row.revision.prefix(12))…")
                                .monospaced()
                            Text(row.license)
                            Spacer()
                            Text(row.byteDescription)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Button(modelDownloadButtonTitle) {
                                startModelDownload(row.kind)
                            }
                            .disabled(row.isInstalled || row.isDownloading)

                            Button("导入本地模型…") {
                                modelImportKind = row.kind
                                isModelImportPresented = true
                            }
                            .disabled(row.isDownloading)
                        }
                    }
                    .padding(.vertical, 3)
                }

                HStack(spacing: 8) {
                    Button("下载全部缺失模型") {
                        startMissingModelDownloads()
                    }
                    .disabled(
                        model.audiobookInstalledKinds.count == SpeechModelKind.allCases.count
                        || model.audiobookModelRows.contains(where: \.isDownloading)
                    )

                    Button("重新扫描本地模型") {
                        localModelManagementError = nil
                        Task { await model.discoverAudiobookModels() }
                    }
                }

                if let error = modelManagementError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                Button("删除听书模型", role: .destructive) {
                    isDeleteModelConfirmationPresented = true
                }
                .disabled(model.audiobookInstalledKinds.isEmpty)

                Text("支持自动识别 Hugging Face 缓存，也可手动下载后导入模型目录。当前仅支持上面两套固定 Qwen 模型与指定 revision，不支持任意 TTS 架构。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("模型只在本机运行，完整下载约 3.8 GB。删除会停止当前听书并移除 ReadBook 管理的模型文件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .confirmationDialog(
                "删除听书模型",
                isPresented: $isDeleteModelConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    Task { await model.deleteAudiobookModels() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后需要重新下载或重新导入才能继续听书。")
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 500, height: 720)
        .task { await model.discoverAudiobookModels() }
        .fileImporter(
            isPresented: $isModelImportPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importModel(modelImportKind, from: url)
            case .failure(let error):
                localModelManagementError = "模型目录选择失败：\(error.localizedDescription)"
            }
        }
    }

    private var currentVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        return "v\(version)"
    }

    private var downloadSourceMode: SpeechModelDownloadSourceMode {
        SpeechModelDownloadSourceMode(rawValue: downloadSourceModeRaw) ?? .huggingFace
    }

    private var configuredDownloadSource: SpeechModelDownloadSource? {
        switch downloadSourceMode {
        case .huggingFace:
            return .huggingFace
        case .customMirror:
            let value = customMirrorURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host != nil else { return nil }
            return SpeechModelDownloadSource(baseURL: url)
        }
    }

    private var modelDownloadButtonTitle: String {
        if case .failed = model.speechModelManager?.state { return "重试" }
        return "下载"
    }

    private var modelManagementError: String? {
        if let localModelManagementError { return localModelManagementError }
        if case .failed(let message) = model.speechModelManager?.state { return message }
        return nil
    }

    private var textColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(nsColor: ThemePalette.readerTextColor(
                    theme: model.preferences.theme,
                    overrideHex: model.preferences.textColorHex
                ))
            },
            set: { color in
                guard let hex = ThemePalette.hexString(for: NSColor(color)) else { return }
                model.updatePreferences { $0.textColorHex = hex }
            }
        )
    }

    private func binding<T>(_ keyPath: WritableKeyPath<ReaderPreferences, T>) -> Binding<T> {
        Binding(
            get: { model.preferences[keyPath: keyPath] },
            set: { value in model.updatePreferences { $0[keyPath: keyPath] = value } }
        )
    }

    private func fontDisplayName(_ font: String) -> String {
        switch font {
        case "PingFang SC": "苹方"
        case "Songti SC": "宋体"
        case "STKaiti": "楷体"
        default: "系统字体"
        }
    }

    private func startModelDownload(_ kind: SpeechModelKind) {
        guard let source = configuredDownloadSource else {
            localModelManagementError = "下载源地址无效，请填写完整的 http:// 或 https:// 地址。"
            return
        }
        localModelManagementError = nil
        Task {
            await model.discoverAudiobookModels()
            await model.speechModelManager?.prepareModel(kind, source: source)
        }
    }

    private func startMissingModelDownloads() {
        guard let source = configuredDownloadSource else {
            localModelManagementError = "下载源地址无效，请填写完整的 http:// 或 https:// 地址。"
            return
        }
        localModelManagementError = nil
        Task {
            await model.discoverAudiobookModels()
            await model.speechModelManager?.prepareMissingModels(source: source)
        }
    }

    private func importModel(_ kind: SpeechModelKind, from url: URL) {
        localModelManagementError = nil
        Task {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            await model.discoverAudiobookModels()
            await model.speechModelManager?.importModel(kind, from: url)
        }
    }

    @ViewBuilder
    private func modelStatusBadge(_ row: SpeechModelRowPresentation) -> some View {
        if row.isDownloading {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                if let fraction = row.progressFraction {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .monospacedDigit()
                } else {
                    Text("下载中")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if row.isInstalled {
            Text("已安装")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Text("未安装")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
