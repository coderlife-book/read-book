import Foundation

public struct VirtualTextWindow: Equatable, Sendable {
    public let text: String
    public let utf16Range: Range<Int>
    public let totalUTF16Length: Int
    public let recenterMargin: Int

    public init(
        text: String,
        utf16Range: Range<Int>,
        totalUTF16Length: Int,
        recenterMargin: Int
    ) {
        self.text = text
        self.utf16Range = utf16Range
        self.totalUTF16Length = totalUTF16Length
        self.recenterMargin = recenterMargin
    }

    public func localOffset(forGlobalOffset offset: Int) -> Int {
        min(max(offset - utf16Range.lowerBound, 0), utf16Range.count)
    }

    public func globalOffset(forLocalOffset offset: Int) -> Int {
        utf16Range.lowerBound + min(max(offset, 0), utf16Range.count)
    }

    public func contains(globalOffset offset: Int) -> Bool {
        offset >= utf16Range.lowerBound && offset <= utf16Range.upperBound
    }

    public func needsRecentering(globalOffset offset: Int) -> Bool {
        let clamped = min(max(offset, utf16Range.lowerBound), utf16Range.upperBound)
        let nearLeadingEdge = utf16Range.lowerBound > 0
            && clamped - utf16Range.lowerBound < recenterMargin
        let nearTrailingEdge = utf16Range.upperBound < totalUTF16Length
            && utf16Range.upperBound - clamped < recenterMargin
        return nearLeadingEdge || nearTrailingEdge
    }
}

public struct VirtualTextWindowPlanner: Sendable {
    public let targetUTF16Length: Int
    public let recenterMargin: Int
    public let paragraphSearchRadius: Int

    public init(
        targetUTF16Length: Int = 120_000,
        recenterMargin: Int = 24_000,
        paragraphSearchRadius: Int = 4_096
    ) {
        self.targetUTF16Length = max(targetUTF16Length, 4_096)
        self.recenterMargin = min(
            max(recenterMargin, 1_024),
            max(targetUTF16Length / 3, 1_024)
        )
        self.paragraphSearchRadius = max(paragraphSearchRadius, 256)
    }

    public func makeWindow(in text: String, centeredAt offset: Int) -> VirtualTextWindow {
        let source = text as NSString
        let total = source.length
        guard total > targetUTF16Length else {
            return VirtualTextWindow(
                text: text,
                utf16Range: 0..<total,
                totalUTF16Length: total,
                recenterMargin: recenterMargin
            )
        }

        let anchor = min(max(offset, 0), total)
        let half = targetUTF16Length / 2
        var lower = max(anchor - half, 0)
        lower = min(lower, total - targetUTF16Length)
        var upper = min(lower + targetUTF16Length, total)

        if lower > 0 {
            lower = paragraphBoundaryBefore(source, offset: lower)
        }
        if upper < total {
            upper = paragraphBoundaryAfter(source, offset: upper)
        }

        let range = lower..<upper
        let snippet = source.substring(
            with: NSRange(location: range.lowerBound, length: range.count)
        )
        return VirtualTextWindow(
            text: snippet,
            utf16Range: range,
            totalUTF16Length: total,
            recenterMargin: recenterMargin
        )
    }

    private func paragraphBoundaryBefore(_ source: NSString, offset: Int) -> Int {
        guard offset > 0 else { return 0 }
        let start = max(offset - paragraphSearchRadius, 0)
        let range = NSRange(location: start, length: offset - start)
        let newline = source.range(of: "\n", options: .backwards, range: range)
        if newline.location != NSNotFound {
            return NSMaxRange(newline)
        }

        let character = min(offset, max(source.length - 1, 0))
        return source.rangeOfComposedCharacterSequence(at: character).location
    }

    private func paragraphBoundaryAfter(_ source: NSString, offset: Int) -> Int {
        guard offset < source.length else { return source.length }
        let end = min(offset + paragraphSearchRadius, source.length)
        let range = NSRange(location: offset, length: end - offset)
        let newline = source.range(of: "\n", options: [], range: range)
        if newline.location != NSNotFound {
            return NSMaxRange(newline)
        }

        return NSMaxRange(source.rangeOfComposedCharacterSequence(at: offset))
    }
}
