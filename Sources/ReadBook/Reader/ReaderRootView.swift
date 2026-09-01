import AppKit
import ReadBookCore
import SwiftUI
import UniformTypeIdentifiers

struct ReaderRootView: View {
    @Bindable var model: AppModel
    let runtime: AppRuntime
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedRecoveryEncoding: ImportedTextEncoding = .gb18030

    var body: some View {
        let palette = ThemePalette.resolve(model.preferences.theme)
        let bodyTextColor = ThemePalette.readerTextColor(
            theme: model.preferences.theme,
            overrideHex: model.preferences.textColorHex
        )
        let style = readerStyle
        let interactiveStealth = runtime.windowState.state == .interactiveStealth
        let bottomVisible = runtime.chrome.bottomVisible || interactiveStealth

        ZStack {
            surfaceBackground(palette: palette)

            if model.currentBook == nil {
                emptyState(textColor: palette.text)
            } else {
                readingSurface(style: style, textColor: bodyTextColor)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { runtime.chrome.bodyEntered() }
                    }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    if bottomVisible {
                        HStack {
                            Text(model.currentChapter?.title ?? "")
                                .lineLimit(1)
                            Spacer()
                            Text("\(model.progressPercent)%")
                                .monospacedDigit()
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(nsColor: palette.secondaryText))
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(controlScrim(palette: palette))
                        .onHover { runtime.chrome.setControlInteractionHeld($0) }
                        .transition(.opacity)
                    }
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Color.clear
                        .frame(height: 16)
                        .contentShape(Rectangle())
                        .onHover { runtime.chrome.bottomZoneChanged(inside: $0) }
                }
                .allowsHitTesting(!isPointerPassThrough)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: model.preferences.windowAppearance == .card ? 26 : 0, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: model.preferences.windowAppearance == .card ? 26 : 0, style: .continuous))
        .animation(.easeOut(duration: 0.14), value: runtime.chrome.topVisible)
        .animation(.easeOut(duration: 0.14), value: runtime.chrome.bottomVisible)
        .popover(
            isPresented: Binding(
                get: { runtime.titlebar.isLibraryPresented },
                set: { runtime.titlebar.isLibraryPresented = $0 }
            ),
            arrowEdge: .top
        ) {
            LibraryPopoverView(model: model)
        }
        .onChange(of: runtime.titlebar.isLibraryPresented) { _, presented in
            runtime.chrome.setControlInteractionHeld(presented)
        }
        .onChange(of: model.currentBook?.title) { _, _ in
            syncTitlebarState()
        }
        .onChange(of: model.readingMode) { _, _ in
            syncTitlebarState()
        }
        .onChange(of: model.preferences.alwaysOnTop) { _, _ in
            syncTitlebarState()
        }
        .onChange(of: runtime.chrome.topVisible) { _, _ in
            syncTitlebarState()
        }
        .onChange(of: runtime.windowState.state) { _, state in
            switch state {
            case .interactiveStealth:
                runtime.chrome.revealAllImmediately()
            case .floatingText, .hidden:
                runtime.chrome.hideAllImmediately()
            case .normal:
                runtime.chrome.hideAllImmediately()
            }
            syncTitlebarState()
        }
        .fileImporter(
            isPresented: $model.isImportPresented,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = ImportDropHandler.firstTXTURL(in: urls) else {
                    model.lastErrorMessage = "目前只支持导入 .txt 小说。"
                    return
                }
                Task { await model.importBook(url) }
            case .failure:
                break
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = ImportDropHandler.firstTXTURL(in: urls) else { return false }
            Task { await model.importBook(url) }
            return true
        }
        .alert(
            "ReadBook",
            isPresented: Binding(
                get: { model.lastErrorMessage != nil && model.encodingRecoveryURL == nil },
                set: { if !$0 { model.lastErrorMessage = nil } }
            )
        ) {
            Button("好") { model.lastErrorMessage = nil }
        } message: {
            Text(model.lastErrorMessage ?? "")
        }
        .sheet(isPresented: Binding(
            get: { model.encodingRecoveryURL != nil },
            set: { if !$0 { model.encodingRecoveryURL = nil } }
        )) {
            encodingRecoverySheet
        }
        .task {
            await model.start()
            syncTitlebarState()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                Task { await model.session.flush() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readBookReaderWillHide)) { _ in
            Task { await model.session.flush() }
        }
    }

    private var isPointerPassThrough: Bool {
        runtime.windowState.state == .floatingText && !runtime.windowState.lockInteractive
    }

    @MainActor
    private func syncTitlebarState() {
        runtime.titlebar.title = model.currentBook?.title ?? "ReadBook"
        runtime.titlebar.readingMode = model.readingMode
        runtime.titlebar.alwaysOnTop = model.preferences.alwaysOnTop
        runtime.titlebar.isVisible = runtime.chrome.topVisible
            || runtime.windowState.state == .interactiveStealth
        runtime.titlebar.onModeChange = { mode in
            model.setMode(mode)
        }
        runtime.titlebar.onPin = {
            model.updatePreferences { $0.alwaysOnTop.toggle() }
            runtime.applyPreferences(model.preferences)
            NotificationCenter.default.post(
                name: .readBookWindowPreferencesChanged,
                object: nil
            )
        }
    }

    @ViewBuilder
    private func readingSurface(style: ReaderTextStyle, textColor: NSColor) -> some View {
        switch model.readingMode {
        case .paginated:
            PaginatedReaderView(
                text: model.text,
                anchor: model.position,
                style: style,
                textColor: textColor,
                onPositionChanged: model.updatePosition
            )
        case .continuous:
            if let bookID = model.currentBook?.id {
                ContinuousReaderView(
                    bookID: bookID,
                    text: model.text,
                    anchor: model.position,
                    style: style,
                    textColor: textColor,
                    onPositionChanged: model.updatePosition
                )
            }
        }
    }

    private func surfaceBackground(palette: ThemePalette) -> some View {
        let color = Color(nsColor: palette.background)
        return Group {
            switch model.preferences.windowAppearance {
            case .card:
                color
            case .frameless:
                color.opacity(model.preferences.framelessBackgroundOpacity)
            case .transparent:
                Color.clear
            }
        }
    }

    private func controlScrim(palette: ThemePalette) -> some View {
        ZStack {
            Color(nsColor: palette.background).opacity(model.preferences.theme == .dark ? 0.94 : 0.96)
            Rectangle().fill(.ultraThinMaterial).opacity(0.18)
        }
    }

    private func emptyState(textColor: NSColor) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 34, weight: .light))
            Text("导入一本 TXT 小说")
                .font(.system(size: 15, weight: .medium))
            Button("选择 TXT…") { model.requestImport() }
                .buttonStyle(.bordered)
        }
        .foregroundStyle(Color(nsColor: textColor))
    }

    private var readerStyle: ReaderTextStyle {
        ReaderTextStyle(
            fontFamily: model.preferences.fontFamily,
            fontSize: model.preferences.fontSize,
            lineSpacing: model.preferences.lineSpacing,
            paragraphSpacing: model.preferences.paragraphSpacing,
            horizontalPadding: 22,
            verticalPadding: 20
        )
    }

    private var encodingRecoverySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("选择文本编码")
                .font(.headline)
            Text("自动识别失败。请选择编码重新导入。")
                .foregroundStyle(.secondary)
            Picker("编码", selection: $selectedRecoveryEncoding) {
                ForEach(ImportedTextEncoding.allCases, id: \.self) { encoding in
                    Text(displayName(encoding)).tag(encoding)
                }
            }
            HStack {
                Spacer()
                Button("取消") {
                    model.encodingRecoveryURL = nil
                    model.lastErrorMessage = nil
                }
                Button("重新导入") {
                    guard let url = model.encodingRecoveryURL else { return }
                    model.encodingRecoveryURL = nil
                    model.lastErrorMessage = nil
                    Task { await model.importBook(url, override: selectedRecoveryEncoding) }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 360)
    }

    private func displayName(_ encoding: ImportedTextEncoding) -> String {
        switch encoding {
        case .utf8: "UTF-8"
        case .utf16LittleEndian: "UTF-16 Little Endian"
        case .utf16BigEndian: "UTF-16 Big Endian"
        case .gb18030: "GB18030 / GBK"
        case .big5: "Big5"
        }
    }
}

extension Notification.Name {
    static let readBookWindowPreferencesChanged = Notification.Name("ReadBook.WindowPreferencesChanged")
    static let readBookReaderWillHide = Notification.Name("ReadBook.ReaderWillHide")
}
