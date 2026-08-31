import AppKit
import Foundation
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

    static func readerTextColor(theme: ReaderTheme, overrideHex: String?) -> NSColor {
        if let overrideHex, let color = color(fromHex: overrideHex) {
            return color
        }
        return resolve(theme).text
    }

    static func color(fromHex hex: String) -> NSColor? {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }

        return NSColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    static func hexString(for color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let red = Int((min(max(rgb.redComponent, 0), 1) * 255).rounded())
        let green = Int((min(max(rgb.greenComponent, 0), 1) * 255).rounded())
        let blue = Int((min(max(rgb.blueComponent, 0), 1) * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
