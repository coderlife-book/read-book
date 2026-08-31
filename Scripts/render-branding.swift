#!/usr/bin/env swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], relativeTo: root).standardizedFileURL
    : root.appendingPathComponent("dist/branding", isDirectory: true)
let iconset = output.appendingPathComponent("ReadBook.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func bitmap(size: Int, draw: (CGFloat) -> Void) throws -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { throw NSError(domain: "ReadBookBranding", code: 1) }
    rep.size = NSSize(width: size, height: size)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "ReadBookBranding", code: 2)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    draw(CGFloat(size))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ReadBookBranding", code: 3)
    }
    return data
}

func drawAppIcon(canvas: CGFloat) {
    let s = canvas / 1024
    let bg = NSBezierPath(
        roundedRect: NSRect(x: 52*s, y: 52*s, width: 920*s, height: 920*s),
        xRadius: 214*s,
        yRadius: 214*s
    )
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.36, green: 0.40, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.35, green: 0.41, blue: 0.85, alpha: 1),
        NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.37, alpha: 1)
    ])!
    gradient.draw(in: bg, angle: -48)

    let page = NSBezierPath()
    page.move(to: NSPoint(x: 286*s, y: 778*s))
    page.curve(to: NSPoint(x: 337*s, y: 829*s), controlPoint1: NSPoint(x: 286*s, y: 806*s), controlPoint2: NSPoint(x: 309*s, y: 829*s))
    page.line(to: NSPoint(x: 618*s, y: 829*s))
    page.curve(to: NSPoint(x: 669*s, y: 778*s), controlPoint1: NSPoint(x: 646*s, y: 829*s), controlPoint2: NSPoint(x: 669*s, y: 806*s))
    page.line(to: NSPoint(x: 669*s, y: 309*s))
    page.curve(to: NSPoint(x: 618*s, y: 257*s), controlPoint1: NSPoint(x: 669*s, y: 280*s), controlPoint2: NSPoint(x: 646*s, y: 257*s))
    page.line(to: NSPoint(x: 402*s, y: 257*s))
    page.curve(to: NSPoint(x: 286*s, y: 373*s), controlPoint1: NSPoint(x: 338*s, y: 257*s), controlPoint2: NSPoint(x: 286*s, y: 309*s))
    page.close()
    NSColor(calibratedWhite: 0.985, alpha: 1).setFill()
    page.fill()

    let fold = NSBezierPath()
    fold.move(to: NSPoint(x: 545*s, y: 829*s))
    fold.line(to: NSPoint(x: 669*s, y: 754*s))
    fold.line(to: NSPoint(x: 669*s, y: 662*s))
    fold.line(to: NSPoint(x: 590*s, y: 662*s))
    fold.curve(to: NSPoint(x: 545*s, y: 707*s), controlPoint1: NSPoint(x: 565*s, y: 662*s), controlPoint2: NSPoint(x: 545*s, y: 682*s))
    fold.close()
    NSColor(calibratedRed: 0.87, green: 0.89, blue: 1.0, alpha: 1).setFill()
    fold.fill()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let r = NSAttributedString(
        string: "R",
        attributes: [
            .font: NSFont.systemFont(ofSize: 295*s, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.35, green: 0.41, blue: 0.85, alpha: 1),
            .paragraphStyle: paragraph
        ]
    )
    r.draw(in: NSRect(x: 340*s, y: 360*s, width: 275*s, height: 315*s))

    let spine = NSBezierPath()
    spine.lineWidth = 18*s
    spine.lineCapStyle = .round
    spine.move(to: NSPoint(x: 402*s, y: 274*s))
    spine.curve(to: NSPoint(x: 302*s, y: 374*s), controlPoint1: NSPoint(x: 346*s, y: 274*s), controlPoint2: NSPoint(x: 302*s, y: 318*s))
    NSColor(calibratedRed: 0.79, green: 0.82, blue: 1.0, alpha: 1).setStroke()
    spine.stroke()
}

func drawMenuMark(canvas: CGFloat) {
    let s = canvas / 24
    let path = NSBezierPath(roundedRect: NSRect(x: 5.4*s, y: 2.8*s, width: 12.8*s, height: 18.4*s), xRadius: 2.0*s, yRadius: 2.0*s)
    path.lineWidth = 1.7*s
    NSColor.black.setStroke()
    path.stroke()

    let fold = NSBezierPath()
    fold.lineWidth = 1.6*s
    fold.move(to: NSPoint(x: 13.2*s, y: 21.0*s))
    fold.line(to: NSPoint(x: 18.0*s, y: 16.2*s))
    NSColor.black.setStroke()
    fold.stroke()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let r = NSAttributedString(string: "R", attributes: [
        .font: NSFont.systemFont(ofSize: 8.8*s, weight: .bold),
        .foregroundColor: NSColor.black,
        .paragraphStyle: paragraph
    ])
    r.draw(in: NSRect(x: 7.0*s, y: 7.0*s, width: 9.6*s, height: 9.5*s))
}

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]
for (name, size) in variants {
    let data = try bitmap(size: size, draw: drawAppIcon)
    try data.write(to: iconset.appendingPathComponent(name), options: .atomic)
}
let menuData = try bitmap(size: 36, draw: drawMenuMark)
try menuData.write(to: output.appendingPathComponent("ReadBookMenuTemplate.png"), options: .atomic)
print(iconset.path)
