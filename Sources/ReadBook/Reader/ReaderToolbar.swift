import ReadBookCore
import SwiftUI

struct ReaderToolbar: View {
    let title: String
    let readingMode: ReadingMode
    let alwaysOnTop: Bool
    let onLibrary: () -> Void
    let onModeChange: (ReadingMode) -> Void
    let onPin: () -> Void
    let audiobookState: SpeechPlaybackState?
    let onAudiobookToggle: () -> Void
    let speechRate: Double
    let onSpeechRateChange: (Double) -> Void

    init(
        title: String,
        readingMode: ReadingMode,
        alwaysOnTop: Bool,
        onLibrary: @escaping () -> Void,
        onModeChange: @escaping (ReadingMode) -> Void,
        onPin: @escaping () -> Void,
        audiobookState: SpeechPlaybackState? = nil,
        onAudiobookToggle: @escaping () -> Void = {},
        speechRate: Double = 1.0,
        onSpeechRateChange: @escaping (Double) -> Void = { _ in }
    ) {
        self.title = title
        self.readingMode = readingMode
        self.alwaysOnTop = alwaysOnTop
        self.onLibrary = onLibrary
        self.onModeChange = onModeChange
        self.onPin = onPin
        self.audiobookState = audiobookState
        self.onAudiobookToggle = onAudiobookToggle
        self.speechRate = speechRate
        self.onSpeechRateChange = onSpeechRateChange
    }

    var body: some View {
        ZStack {
            ReaderDragRegion()
                .help("拖动窗口")

            HStack(spacing: 8) {
                Button(action: onLibrary) {
                    ToolbarIconLabel(systemName: "books.vertical")
                }
                .help("目录与最近阅读")

                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)

                Button {
                    onModeChange(readingMode == .paginated ? .continuous : .paginated)
                } label: {
                    ToolbarIconLabel(
                        systemName: readingMode == .paginated ? "rectangle.split.1x2" : "text.justify"
                    )
                }
                .help(readingMode == .paginated ? "切换到滚动阅读" : "切换到分页阅读")

                if let audiobookState {
                    Button(action: onAudiobookToggle) {
                        ToolbarIconLabel(systemName: audiobookState == .playing ? "pause.fill" : "headphones")
                    }
                    .help(audiobookState == .playing ? "暂停听书" : "开始听书")
                }

                Menu {
                    ForEach(0..<11, id: \.self) { index in
                        let rate = 0.5 + Double(index) * 0.1
                        Button {
                            onSpeechRateChange(rate)
                        } label: {
                            HStack {
                                Text(String(format: "%.1fx", rate))
                                if abs(rate - speechRate) < 0.001 { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Text(String(format: "%.1fx", speechRate))
                        .frame(minWidth: 34, minHeight: 30)
                }
                .help("听书速度")

                Button(action: onPin) {
                    ToolbarIconLabel(systemName: alwaysOnTop ? "pin.fill" : "pin")
                }
                .help(alwaysOnTop ? "取消置顶" : "始终置顶")

                SettingsLink {
                    ToolbarIconLabel(systemName: "ellipsis")
                }
                .help("设置")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 14)
        .frame(height: 42)
    }
}

private struct ToolbarIconLabel: View {
    let systemName: String
    @State private var isHovered = false

    var body: some View {
        Image(systemName: systemName)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .background {
                Circle()
                    .fill(Color.gray.opacity(isHovered ? 0.16 : 0))
            }
            .background {
                ToolbarButtonCursorRegion()
            }
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.10), value: isHovered)
    }
}

private struct ToolbarButtonCursorRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> ToolbarButtonCursorView {
        ToolbarButtonCursorView()
    }

    func updateNSView(_ nsView: ToolbarButtonCursorView, context: Context) {}
}

private final class ToolbarButtonCursorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }
}
