import AppKit

final class ReaderResizeView: NSView {
    private enum ResizeEdge {
        case left
        case right
        case top
        case bottom
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight

        var cursorPosition: NSCursor.FrameResizePosition {
            switch self {
            case .left: .left
            case .right: .right
            case .top: .top
            case .bottom: .bottom
            case .topLeft: .topLeft
            case .topRight: .topRight
            case .bottomLeft: .bottomLeft
            case .bottomRight: .bottomRight
            }
        }

        var movesLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
        var movesRight: Bool { self == .right || self == .topRight || self == .bottomRight }
        var movesTop: Bool { self == .top || self == .topLeft || self == .topRight }
        var movesBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
    }

    private static let edgeThickness: CGFloat = 6
    private static let cornerExtent: CGFloat = 12

    private var activeEdge: ResizeEdge?
    private var dragStartFrame: NSRect?
    private var dragStartScreenPoint: NSPoint?

    override var acceptsFirstResponder: Bool { false }
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        resizeEdge(at: point) == nil ? nil : self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard bounds.width > 0, bounds.height > 0 else { return }

        let edge = Self.edgeThickness
        let corner = min(Self.cornerExtent, min(bounds.width, bounds.height) / 2)
        let middleWidth = max(bounds.width - (corner * 2), 0)
        let middleHeight = max(bounds.height - (corner * 2), 0)

        addCursorRect(NSRect(x: 0, y: 0, width: corner, height: corner), cursor: cursor(for: .bottomLeft))
        addCursorRect(NSRect(x: bounds.maxX - corner, y: 0, width: corner, height: corner), cursor: cursor(for: .bottomRight))
        addCursorRect(NSRect(x: 0, y: bounds.maxY - corner, width: corner, height: corner), cursor: cursor(for: .topLeft))
        addCursorRect(NSRect(x: bounds.maxX - corner, y: bounds.maxY - corner, width: corner, height: corner), cursor: cursor(for: .topRight))

        addCursorRect(NSRect(x: 0, y: corner, width: edge, height: middleHeight), cursor: cursor(for: .left))
        addCursorRect(NSRect(x: bounds.maxX - edge, y: corner, width: edge, height: middleHeight), cursor: cursor(for: .right))
        addCursorRect(NSRect(x: corner, y: 0, width: middleWidth, height: edge), cursor: cursor(for: .bottom))
        addCursorRect(NSRect(x: corner, y: bounds.maxY - edge, width: middleWidth, height: edge), cursor: cursor(for: .top))
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let edge = resizeEdge(at: point) else {
            NSCursor.arrow.set()
            return
        }
        cursor(for: edge).set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let edge = resizeEdge(at: point) else { return }

        activeEdge = edge
        dragStartFrame = window.frame
        dragStartScreenPoint = window.convertPoint(toScreen: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let window,
            let activeEdge,
            let dragStartFrame,
            let dragStartScreenPoint
        else { return }

        let current = window.convertPoint(toScreen: event.locationInWindow)
        let delta = NSPoint(
            x: current.x - dragStartScreenPoint.x,
            y: current.y - dragStartScreenPoint.y
        )
        let frame = resizedFrame(
            from: dragStartFrame,
            edge: activeEdge,
            delta: delta,
            minimumSize: window.minSize
        )
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        activeEdge = nil
        dragStartFrame = nil
        dragStartScreenPoint = nil
        super.mouseUp(with: event)
    }

    private func resizeEdge(at point: NSPoint) -> ResizeEdge? {
        guard bounds.contains(point) else { return nil }

        let edge = Self.edgeThickness
        let corner = Self.cornerExtent
        let nearLeftCorner = point.x <= corner
        let nearRightCorner = point.x >= bounds.maxX - corner
        let nearBottomCorner = point.y <= corner
        let nearTopCorner = point.y >= bounds.maxY - corner

        if nearLeftCorner && nearBottomCorner { return .bottomLeft }
        if nearRightCorner && nearBottomCorner { return .bottomRight }
        if nearLeftCorner && nearTopCorner { return .topLeft }
        if nearRightCorner && nearTopCorner { return .topRight }
        if point.x <= edge { return .left }
        if point.x >= bounds.maxX - edge { return .right }
        if point.y <= edge { return .bottom }
        if point.y >= bounds.maxY - edge { return .top }
        return nil
    }

    private func cursor(for edge: ResizeEdge) -> NSCursor {
        NSCursor.frameResize(position: edge.cursorPosition, directions: .all)
    }

    private func resizedFrame(
        from start: NSRect,
        edge: ResizeEdge,
        delta: NSPoint,
        minimumSize: NSSize
    ) -> NSRect {
        var frame = start

        if edge.movesLeft {
            let newMinX = min(start.minX + delta.x, start.maxX - minimumSize.width)
            frame.origin.x = newMinX
            frame.size.width = start.maxX - newMinX
        } else if edge.movesRight {
            frame.size.width = max(minimumSize.width, start.width + delta.x)
        }

        if edge.movesBottom {
            let newMinY = min(start.minY + delta.y, start.maxY - minimumSize.height)
            frame.origin.y = newMinY
            frame.size.height = start.maxY - newMinY
        } else if edge.movesTop {
            frame.size.height = max(minimumSize.height, start.height + delta.y)
        }

        return frame
    }
}
