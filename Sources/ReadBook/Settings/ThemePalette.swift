import AppKit
import ReadBookCore

struct ThemePalette {
    let background: NSColor
    let text: NSColor
    let secondaryText: NSColor
    let controlBackground: NSColor

    static func resolve(_ theme: ReaderTheme) -> ThemePalette {
        switch theme {
        case .soft:
            return ThemePalette(
                background: NSColor(calibratedRed: 0.965, green: 0.952, blue: 0.925, alpha: 1),
                text: NSColor(calibratedWhite: 0.16, alpha: 1),
                secondaryText: NSColor(calibratedWhite: 0.42, alpha: 1),
                controlBackground: NSColor(calibratedWhite: 1, alpha: 0.72)
            )
        case .light:
            return ThemePalette(
                background: NSColor(calibratedWhite: 0.99, alpha: 1),
                text: NSColor(calibratedWhite: 0.10, alpha: 1),
                secondaryText: .secondaryLabelColor,
                controlBackground: NSColor(calibratedWhite: 0.94, alpha: 0.85)
            )
        case .dark:
            return ThemePalette(
                background: NSColor(calibratedWhite: 0.12, alpha: 1),
                text: NSColor(calibratedWhite: 0.88, alpha: 1),
                secondaryText: NSColor(calibratedWhite: 0.65, alpha: 1),
                controlBackground: NSColor(calibratedWhite: 0.22, alpha: 0.88)
            )
        }
    }
}
