import AppKit
import SwiftUI

@main
@MainActor
struct ReadBookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    private let windowRegistry = WindowRegistry()

    var body: some Scene {
        Window("ReadBook", id: "reader") {
            ReaderRootView(model: model)
                .frame(minWidth: 280, minHeight: 180)
                .task {
                    appDelegate.flushHandler = { @MainActor in
                        await model.session.flush()
                    }
                }
                .background {
                    WindowAccessor { window in
                        windowRegistry.register(window)
                        windowRegistry.apply(model.preferences)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .readBookWindowPreferencesChanged)) { _ in
                    windowRegistry.apply(model.preferences)
                }
        }
        .defaultSize(width: 360, height: 260)
        .commands {
            CommandGroup(after: .newItem) {
                Button("导入 TXT…") {
                    windowRegistry.showReader()
                    model.requestImport()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        MenuBarExtra("ReadBook", systemImage: "book.closed") {
            Button("显示 / 隐藏阅读器") {
                windowRegistry.toggleReader()
            }

            if !model.books.isEmpty {
                Divider()
                ForEach(model.books.prefix(6)) { book in
                    Button(book.title) {
                        Task {
                            try? await model.open(book.id)
                            windowRegistry.showReader()
                        }
                    }
                }
            }

            Divider()
            Button("导入 TXT…") {
                windowRegistry.showReader()
                model.requestImport()
            }
            SettingsLink { Text("设置…") }
            Divider()
            Button("退出 ReadBook") {
                NSApp.terminate(nil)
            }
        }

        Settings {
            SettingsView(model: model, windowRegistry: windowRegistry)
        }
    }
}
