import AppKit
import LittleSwitchCore

@MainActor
enum ApplicationConfirmationAlert {
    static func make(message: String, actionTitle: String, cancelTitle: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = ProductIdentity.displayName
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: actionTitle)
        let cancel = alert.addButton(withTitle: cancelTitle)
        // AppKit only infers Escape for the literal English title "Cancel".
        cancel.keyEquivalent = "\u{1b}"
        cancel.keyEquivalentModifierMask = []
        return alert
    }
}
