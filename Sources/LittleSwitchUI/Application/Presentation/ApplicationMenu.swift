import AppKit
import LittleSwitchCore

enum ApplicationMenuFactory {
    static func make() -> NSMenu {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(
            title: ProductIdentity.displayName,
            action: nil,
            keyEquivalent: ""
        )
        appItem.submenu = appMenu()
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem(title: L10n.string("Edit"), action: nil, keyEquivalent: "")
        editItem.submenu = editMenu()
        mainMenu.addItem(editItem)
        return mainMenu
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: ProductIdentity.displayName)
        menu.addItem(
            command(
                L10n.string("About \(ProductIdentity.displayName)"),
                action: "showAbout",
                key: ""
            )
        )
        // The application delegate implements the selector: NSApp.delegate
        // participates in the menu-action responder chain.
        menu.addItem(
            command(
                L10n.string("Check for Updates…"),
                action: "checkForUpdates:",
                key: ""
            )
        )
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.string("Edit"))
        menu.addItem(command(L10n.string("Undo"), action: "undo:", key: "z"))
        menu.addItem(
            command(
                L10n.string("Redo"),
                action: "redo:",
                key: "z",
                modifiers: [.command, .shift]
            )
        )
        menu.addItem(.separator())
        menu.addItem(command(L10n.string("Cut"), action: "cut:", key: "x"))
        menu.addItem(command(L10n.string("Copy"), action: "copy:", key: "c"))
        menu.addItem(command(L10n.string("Paste"), action: "paste:", key: "v"))
        menu.addItem(command(L10n.string("Select All"), action: "selectAll:", key: "a"))
        return menu
    }

    private static func command(
        _ title: String,
        action: String,
        key: String,
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: NSSelectorFromString(action),
            keyEquivalent: key
        )
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
