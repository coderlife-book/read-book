@preconcurrency import AppKit

final class ReaderTextLayoutDelegate: NSObject, NSLayoutManagerDelegate {
    var lineSpacing: CGFloat = 0

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        baselineOffset.pointee += lineSpacing / 2
        return true
    }
}
