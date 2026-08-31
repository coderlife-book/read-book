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
            .frame(height: 30)

            Button {
                onModeChange(readingMode == .paginated ? .continuous : .paginated)
            } label: {
                ToolbarIconLabel(
                    systemName: readingMode == .paginated ? "rectangle.split.1x2" : "text.justify"
                )
            }
            .help(readingMode == .paginated ? "切换到滚动阅读" : "切换到分页阅读")

            Button(action: onPin) {
                ToolbarIconLabel(systemName: alwaysOnTop ? "pin.fill" : "pin")
            }
            .help(alwaysOnTop ? "取消置顶" : "始终置顶")

            SettingsLink {
                ToolbarIconLabel(systemName: "ellipsis")
            }
            .help("设置")
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
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.10), value: isHovered)
    }
}
