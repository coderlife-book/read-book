import AppKit
import SwiftUI

@MainActor
final class ReaderTitlebarButtonHostView: NSView {
    private let state: ReaderTitlebarState
    private let hostingView: NSHostingView<AnyView>

    init(state: ReaderTitlebarState, rootView: AnyView) {
        self.state = state
        self.hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)

        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)

        let size = hostingView.fittingSize
        frame.size = NSSize(
            width: max(size.width, 30),
            height: max(size.height, 30)
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let size = hostingView.fittingSize
        return NSSize(
            width: max(size.width, 30),
            height: max(size.height, 30)
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard state.isVisible else { return nil }
        return super.hitTest(point)
    }
}

@MainActor
final class ReaderTitlebarPassthroughHostView: NSView {
    private let hostingView: NSHostingView<AnyView>

    init(rootView: AnyView) {
        self.hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)

        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)

        let size = hostingView.fittingSize
        frame.size = size
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        hostingView.fittingSize
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

@MainActor
struct ReaderTitlebarLibraryItemView: View {
    @Bindable var state: ReaderTitlebarState

    var body: some View {
        Button {
            state.toggleLibrary()
        } label: {
            ReaderTitlebarIconLabel(systemName: "books.vertical")
        }
        .buttonStyle(.plain)
        .help("目录与最近阅读")
        .opacity(state.isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.14), value: state.isVisible)
        .frame(width: 30, height: 30)
    }
}

@MainActor
struct ReaderTitlebarTitleItemView: View {
    @Bindable var state: ReaderTitlebarState

    var body: some View {
        Text(state.title)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .opacity(state.isVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.14), value: state.isVisible)
            .frame(width: 132, height: 30, alignment: .leading)
            .allowsHitTesting(false)
    }
}

@MainActor
struct ReaderTitlebarModeItemView: View {
    @Bindable var state: ReaderTitlebarState

    var body: some View {
        Button {
            state.toggleReadingMode()
        } label: {
            ReaderTitlebarIconLabel(
                systemName: state.readingMode == .paginated
                    ? "rectangle.split.1x2"
                    : "text.justify"
            )
        }
        .buttonStyle(.plain)
        .help(state.readingMode == .paginated ? "切换到滚动阅读" : "切换到分页阅读")
        .opacity(state.isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.14), value: state.isVisible)
        .frame(width: 30, height: 30)
    }
}

@MainActor
struct ReaderTitlebarPinItemView: View {
    @Bindable var state: ReaderTitlebarState

    var body: some View {
        Button {
            state.togglePin()
        } label: {
            ReaderTitlebarIconLabel(systemName: state.alwaysOnTop ? "pin.fill" : "pin")
        }
        .buttonStyle(.plain)
        .help(state.alwaysOnTop ? "取消置顶" : "始终置顶")
        .opacity(state.isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.14), value: state.isVisible)
        .frame(width: 30, height: 30)
    }
}

@MainActor
struct ReaderTitlebarSettingsItemView: View {
    @Bindable var state: ReaderTitlebarState

    var body: some View {
        SettingsLink {
            ReaderTitlebarIconLabel(systemName: "ellipsis")
        }
        .buttonStyle(.plain)
        .help("设置")
        .opacity(state.isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.14), value: state.isVisible)
        .frame(width: 30, height: 30)
    }
}

private struct ReaderTitlebarIconLabel: View {
    let systemName: String
    @State private var hovered = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .medium))
            .frame(width: 30, height: 30)
            .contentShape(Circle())
            .background {
                Circle()
                    .fill(Color.secondary.opacity(hovered ? 0.12 : 0))
            }
            .onHover { hovered = $0 }
    }
}
