import ReadBookCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    let runtime: AppRuntime

    private let fonts = ["PingFang SC", "Songti SC", "STKaiti", "System"]

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
                    Text("隐蔽（移出隐藏）").tag(BossModeProfile.concealed)
                }

                Toggle("锁定为可交互（本次运行）", isOn: Binding(
                    get: { runtime.windowState.lockInteractive },
                    set: { runtime.setLockInteractive($0) }
                ))

                LabeledContent("紧急隐藏") {
                    Text("⌃⌥R")
                        .monospaced()
                }

                Text("透明悬浮时鼠标默认穿透到后面的工作软件；按住 Option 可临时操作阅读器。正文区域悬停和滚动不会再唤出标题栏或章节栏。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !runtime.hotKeyAvailable {
                    Text("当前全局快捷键未注册成功，仍可通过菜单栏显示/隐藏阅读器。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
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
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 470, height: 640)
    }

    private var currentVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        return "v\(version)"
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
}
