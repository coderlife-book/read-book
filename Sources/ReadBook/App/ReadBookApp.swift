import AppKit
import SwiftUI

@main
@MainActor
struct ReadBookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    private let runtime = AppRuntime()

    var body: some Scene {
        Window("ReadBook", id: "reader") {
            ReaderRootView(model: model, runtime: runtime)
                .frame(minWidth: 280, minHeight: 180)
                .task {
                    appDelegate.flushHandler = { @MainActor in
                        await model.session.flush()
                    }
                    appDelegate.cleanupHandler = { @MainActor in
                        runtime.stop()
                    }
                    runtime.configureUpdater {
                        await model.session.flush()
                    }
                    runtime.start(preferences: model.preferences)
                }
                .background {
                    WindowAccessor { window in
                        runtime.register(window: window)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .readBookWindowPreferencesChanged)) { _ in
                    runtime.applyPreferences(model.preferences)
                }
                .sheet(isPresented: Binding(
                    get: { runtime.updater.isPresented },
                    set: { if !$0 { runtime.updater.dismiss() } }
                )) {
                    UpdatePromptView(controller: runtime.updater)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 360, height: 260)
        .commands {
            CommandGroup(after: .newItem) {
                Button("导入 TXT…") {
                    runtime.showReader()
                    model.requestImport()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("检查更新…") {
                    runtime.showReader()
                    Task { await runtime.updater.check(manual: true) }
                }
            }
        }

        MenuBarExtra {
            Button("显示 / 隐藏阅读器") {
                runtime.toggleReaderFromMenu()
            }

            Divider()

            Toggle("老板模式", isOn: Binding(
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

            Menu("老板模式行为") {
                Button("悬浮阅读") {
                    runtime.setBossProfile(.floatingReading, using: model)
                }
                Button("隐蔽") {
                    runtime.setBossProfile(.concealed, using: model)
                }
            }

            Toggle("锁定为可交互", isOn: Binding(
                get: { runtime.windowState.lockInteractive },
                set: { runtime.setLockInteractive($0) }
            ))

            Menu("窗口外观") {
                Button("卡片") { runtime.setAppearance(.card, using: model) }
                Button("无边框") { runtime.setAppearance(.frameless, using: model) }
                Button("纯透明") { runtime.setAppearance(.transparent, using: model) }
            }

            Text("安全模式：不监听全局键盘/鼠标")
                .foregroundStyle(.secondary)

            if !model.books.isEmpty {
                Divider()
                ForEach(model.books.prefix(6)) { book in
                    Button(book.title) {
                        Task {
                            try? await model.open(book.id)
                            runtime.showReader()
                        }
                    }
                }
            }

            Divider()
            Button("导入 TXT…") {
                runtime.showReader()
                model.requestImport()
            }
            Button("检查更新…") {
                runtime.showReader()
                Task { await runtime.updater.check(manual: true) }
            }
            SettingsLink { Text("设置…") }
            Divider()
            Button("退出 ReadBook") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(nsImage: ReadBookBrand.menuBarImage)
        }

        Settings {
            SettingsView(model: model, runtime: runtime)
        }
    }
}
