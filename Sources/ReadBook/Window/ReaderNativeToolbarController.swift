import AppKit
import SwiftUI

extension NSToolbarItem.Identifier {
    static let readBookLibrary = NSToolbarItem.Identifier("ReadBook.Library")
    static let readBookTitle = NSToolbarItem.Identifier("ReadBook.Title")
    static let readBookMode = NSToolbarItem.Identifier("ReadBook.Mode")
    static let readBookPin = NSToolbarItem.Identifier("ReadBook.Pin")
    static let readBookSettings = NSToolbarItem.Identifier("ReadBook.Settings")
}

@MainActor
final class ReaderNativeToolbarController: NSObject, NSToolbarDelegate {
    private var state: ReaderTitlebarState?

    func install(on window: NSWindow, state: ReaderTitlebarState) {
        self.state = state

        let toolbar = NSToolbar(identifier: "ReadBook.ReaderToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly

        window.toolbarStyle = .unifiedCompact
        window.toolbar = toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .readBookLibrary,
            .readBookTitle,
            .flexibleSpace,
            .readBookMode,
            .readBookPin,
            .readBookSettings,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let state else { return nil }

        switch itemIdentifier {
        case .readBookLibrary:
            return buttonItem(
                identifier: itemIdentifier,
                label: "书库",
                state: state,
                rootView: AnyView(ReaderTitlebarLibraryItemView(state: state))
            )
        case .readBookTitle:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "书名"
            item.paletteLabel = "书名"
            let host = ReaderTitlebarPassthroughHostView(
                rootView: AnyView(ReaderTitlebarTitleItemView(state: state))
            )
            host.frame = NSRect(x: 0, y: 0, width: 132, height: 30)
            item.view = host
            return item
        case .readBookMode:
            return buttonItem(
                identifier: itemIdentifier,
                label: "阅读模式",
                state: state,
                rootView: AnyView(ReaderTitlebarModeItemView(state: state))
            )
        case .readBookPin:
            return buttonItem(
                identifier: itemIdentifier,
                label: "置顶",
                state: state,
                rootView: AnyView(ReaderTitlebarPinItemView(state: state))
            )
        case .readBookSettings:
            return buttonItem(
                identifier: itemIdentifier,
                label: "设置",
                state: state,
                rootView: AnyView(ReaderTitlebarSettingsItemView(state: state))
            )
        default:
            return nil
        }
    }

    private func buttonItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        state: ReaderTitlebarState,
        rootView: AnyView
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label

        let host = ReaderTitlebarButtonHostView(state: state, rootView: rootView)
        host.frame = NSRect(x: 0, y: 0, width: 30, height: 30)
        item.view = host
        return item
    }
}
