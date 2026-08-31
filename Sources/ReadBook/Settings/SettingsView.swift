import ReadBookCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    let windowRegistry: WindowRegistry

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
            }

            Section("窗口") {
                Toggle("始终置顶", isOn: Binding(
                    get: { model.preferences.alwaysOnTop },
                    set: { value in
                        model.updatePreferences { $0.alwaysOnTop = value }
                        windowRegistry.setAlwaysOnTop(value)
                    }
                ))

                Picker("应用模式", selection: Binding(
                    get: { model.preferences.appPresenceMode },
                    set: { value in
                        model.updatePreferences { $0.appPresenceMode = value }
                        windowRegistry.setAppPresence(value)
                    }
                )) {
                    Text("小组件模式（隐藏 Dock）").tag(AppPresenceMode.widgetStyle)
                    Text("普通 App（显示 Dock）").tag(AppPresenceMode.normal)
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 440, height: 330)
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
