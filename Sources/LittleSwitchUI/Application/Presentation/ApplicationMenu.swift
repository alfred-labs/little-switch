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
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu()
        mainMenu.addItem(editItem)
        return mainMenu
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: ProductIdentity.displayName)
        menu.addItem(
            command(
                "About \(ProductIdentity.displayName)",
                action: "orderFrontStandardAboutPanel:",
                key: ""
            )
        )
        // The application delegate implements the selector: NSApp.delegate
        // participates in the menu-action responder chain.
        menu.addItem(
            command(
                "Check for Updates…",
                action: "checkForUpdates:",
                key: ""
            )
        )
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(command("Undo", action: "undo:", key: "z"))
        menu.addItem(
            command(
                "Redo",
                action: "redo:",
                key: "z",
                modifiers: [.command, .shift]
            )
        )
        menu.addItem(.separator())
        menu.addItem(command("Cut", action: "cut:", key: "x"))
        menu.addItem(command("Copy", action: "copy:", key: "c"))
        menu.addItem(command("Paste", action: "paste:", key: "v"))
        menu.addItem(command("Select All", action: "selectAll:", key: "a"))
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
