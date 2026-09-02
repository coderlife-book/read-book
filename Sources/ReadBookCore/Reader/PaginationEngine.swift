import Foundation

public struct PageRange: Equatable, Hashable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public var upperBound: Int { location + length }
}

#if canImport(AppKit)
import AppKit

public struct PaginationEngine: Sendable {
    private let probeLimit = 65_536

    public init() {}

    public func pageForward(
        text: NSString,
        from rawOffset: Int,
        width: Double,
        height: Double,
        style: ReaderTextStyle
    ) -> PageRange? {
        let offset = min(max(rawOffset, 0), text.length)
        guard offset < text.length else { return nil }

        let safeOffset = composedBoundary(in: text, at: offset)
        let available = min(probeLimit, text.length - safeOffset)
        let fragment = text.substring(with: NSRange(location: safeOffset, length: available))
        let fitting = fittingUTF16Length(fragment, width: width, height: height, style: style)
        guard fitting > 0 else { return nil }
        return PageRange(location: safeOffset, length: min(fitting, available))
    }

    public func pageBackward(
        text: NSString,
        endingAt rawOffset: Int,
        width: Double,
        height: Double,
        style: ReaderTextStyle
    ) -> PageRange? {
        let end = min(max(rawOffset, 0), text.length)
        guard end > 0 else { return nil }

        let lowerBound = max(0, end - probeLimit)
        var low = lowerBound
        var high = end - 1
        var bestStart = end - 1

        while low <= high {
            let mid = (low + high) / 2
            let safeStart = composedBoundary(in: text, at: mid)
            let length = end - safeStart
            guard length > 0 else {
                high = mid - 1
                continue
            }

            let fragment = text.substring(with: NSRange(location: safeStart, length: length))
            let fitting = fittingUTF16Length(fragment, width: width, height: height, style: style)
            if fitting >= length {
                bestStart = safeStart
                high = mid - 1
            } else {
                low = mid + 1
            }
        }

        let length = end - bestStart
        return length > 0 ? PageRange(location: bestStart, length: length) : nil
    }

    public func attributedString(_ text: String, style: ReaderTextStyle) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        let balancedLineSpacing = style.lineSpacing / 2
        paragraph.lineSpacing = balancedLineSpacing
        paragraph.paragraphSpacing = style.paragraphSpacing
        let font: NSFont
        if style.fontFamily == "System" {
            font = .systemFont(ofSize: style.fontSize)
        } else {
            font = NSFont(name: style.fontFamily, size: style.fontSize) ?? .systemFont(ofSize: style.fontSize)
        }
        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraph,
                .baselineOffset: -balancedLineSpacing,
            ]
        )
    }

    private func fittingUTF16Length(
        _ fragment: String,
        width: Double,
        height: Double,
        style: ReaderTextStyle
    ) -> Int {
        let attributed = attributedString(fragment, style: style)
        let storage = NSTextStorage(attributedString: attributed)
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true
        let container = NSTextContainer(size: NSSize(width: max(width, 1), height: max(height, 1)))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        let glyphRange = layout.glyphRange(for: container)
        guard glyphRange.length > 0 else { return 0 }
        return layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil).length
    }

    private func composedBoundary(in text: NSString, at index: Int) -> Int {
        let clamped = min(max(index, 0), text.length)
        guard text.length > 0, clamped < text.length else { return clamped }
        return text.rangeOfComposedCharacterSequence(at: clamped).location
    }
}
#endif
