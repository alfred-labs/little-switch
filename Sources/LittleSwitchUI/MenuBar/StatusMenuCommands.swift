import AppKit

/// Shared native footer commands for every tab. Settings stays available
/// through its shortcut while the header gear owns its visible entry point.
@MainActor
enum StatusMenuCommands {
    static func makeItems(target: AnyObject?) -> [NSMenuItem] {
        let settings = item(
            L10n.string("Settings…"),
            symbol: "gearshape",
            key: ",",
            action: #selector(LittleSwitchApplicationDelegate.showMainWindow),
            target: target
        )
        settings.isHidden = true
        return [
            settings,
            .separator(),
            item(
                L10n.string("About LittleSwitch"),
                symbol: "info.circle",
                action: #selector(LittleSwitchApplicationDelegate.showAbout),
                target: target
            ),
            item(
                L10n.string("Check for Updates…"),
                symbol: "arrow.triangle.2.circlepath",
                action: #selector(LittleSwitchApplicationDelegate.checkForUpdates(_:)),
                target: target
            ),
            item(
                L10n.string("Quit LittleSwitch"),
                symbol: "rectangle.portrait.and.arrow.right",
                key: "q",
                action: #selector(LittleSwitchApplicationDelegate.quit),
                target: target
            ),
        ]
    }

    private static func item(
        _ title: String, symbol: String, key: String = "", action: Selector, target: AnyObject?
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        item.keyEquivalentModifierMask = [.command]
        item.allowsKeyEquivalentWhenHidden = true
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image?.isTemplate = true
        image?.size = NSSize(width: 14, height: 14)
        item.image = image
        return item
    }
}
