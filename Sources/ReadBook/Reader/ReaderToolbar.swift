import ReadBookCore
import SwiftUI

struct ReaderToolbar: View {
    let title: String
    let readingMode: ReadingMode
    let alwaysOnTop: Bool
    let onLibrary: () -> Void
    let onModeChange: (ReadingMode) -> Void
    let onPin: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onLibrary) {
                Image(systemName: "books.vertical")
            }
            .help("目录与最近阅读")

            ZStack(alignment: .leading) {
                ReaderDragRegion()
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .help("拖动窗口")

            Button {
                onModeChange(readingMode == .paginated ? .continuous : .paginated)
            } label: {
                Image(systemName: readingMode == .paginated ? "rectangle.split.1x2" : "text.justify")
            }
            .help(readingMode == .paginated ? "切换到滚动阅读" : "切换到分页阅读")

            Button(action: onPin) {
                Image(systemName: alwaysOnTop ? "pin.fill" : "pin")
            }
            .help(alwaysOnTop ? "取消置顶" : "始终置顶")

            SettingsLink {
                Image(systemName: "ellipsis")
            }
            .help("设置")
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 14)
        .frame(height: 42)
    }
}
