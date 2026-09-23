import AppKit
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Application confirmation keyboard behavior")
struct ApplicationConfirmationAlertTests {
    @Test("Localized confirmations keep Return and Escape independent of button titles", arguments: ["en", "fr"])
    func localizedKeyboardActions(language: String) throws {
        let locale = Locale(identifier: language)
        let actionTitle = L10n.string("Continue", locale: locale)
        let cancelTitle = L10n.string("Cancel", locale: locale)
        let alert = ApplicationConfirmationAlert.make(
            message: "Synthetic confirmation",
            actionTitle: actionTitle,
            cancelTitle: cancelTitle
        )

        #expect(alert.buttons.map(\.title) == [actionTitle, cancelTitle])
        #expect(alert.informativeText == "Synthetic confirmation")
        #expect(alert.alertStyle == .warning)
        let action = try #require(alert.buttons.first)
        let cancel = try #require(alert.buttons.last)
        #expect(action.keyEquivalent == "\r")
        #expect(action.keyEquivalentModifierMask.isEmpty)
        #expect(cancel.keyEquivalent == "\u{1b}")
        #expect(cancel.keyEquivalentModifierMask.isEmpty)
    }
}
