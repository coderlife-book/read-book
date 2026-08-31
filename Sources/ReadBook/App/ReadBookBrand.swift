import AppKit

@MainActor
enum ReadBookBrand {
    static var menuBarImage: NSImage {
        if let url = Bundle.main.url(forResource: "ReadBookMenuTemplate", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }
        return NSImage(systemSymbolName: "book.closed", accessibilityDescription: "ReadBook") ?? NSImage()
    }
}
