import AppKit
import ReadBookCore
import SwiftUI
import UniformTypeIdentifiers

struct ReaderRootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var hovering = false
    @State private var showLibrary = false
    @State private var selectedRecoveryEncoding: ImportedTextEncoding = .gb18030

    var body: some View {
        let palette = ThemePalette.resolve(model.preferences.theme)
        let style = readerStyle

        ZStack {
            Color(nsColor: palette.background)

            if model.currentBook == nil {
                emptyState(textColor: palette.text)
            } else {
                readingSurface(style: style, palette: palette)

                VStack(spacing: 0) {
                    ReaderToolbar(
                        title: model.currentBook?.title ?? "ReadBook",
                        readingMode: model.readingMode,
                        alwaysOnTop: model.preferences.alwaysOnTop,
                        onLibrary: { showLibrary.toggle() },
                        onModeChange: { model.setMode($0) },
                        onPin: {
                            model.updatePreferences { $0.alwaysOnTop.toggle() }
                            NotificationCenter.default.post(name: .readBookWindowPreferencesChanged, object: nil)
                        }
                    )
                    .opacity(hovering ? 1 : 0)
                    .allowsHitTesting(hovering)

                    Spacer()

                    if hovering {
                        HStack {
                            Text(model.currentChapter?.title ?? "")
                                .lineLimit(1)
                            Spacer()
                            Text("\(model.progressPercent)%")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: palette.secondaryText))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 11)
                        .transition(.opacity)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .popover(isPresented: $showLibrary, arrowEdge: .top) {
            LibraryPopoverView(model: model)
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
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                Task { await model.session.flush() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readBookReaderWillHide)) { _ in
            Task { await model.session.flush() }
        }
    }

    @ViewBuilder
    private func readingSurface(style: ReaderTextStyle, palette: ThemePalette) -> some View {
        switch model.readingMode {
        case .paginated:
            PaginatedReaderView(
                text: model.text,
                anchor: model.position,
                style: style,
                textColor: palette.text,
                onPositionChanged: model.updatePosition
            )
        case .continuous:
            ContinuousReaderView(
                text: model.text,
                anchor: model.position,
                style: style,
                textColor: palette.text,
                onPositionChanged: model.updatePosition
            )
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
