import AppKit
import LittleSwitchCore

extension LittleSwitchApplicationDelegate {
    func present(_ error: any Swift.Error) {
        model.isBusy = false
        model.errorMessage = startupErrorMessage(for: error)
    }

    func presentStartupFailure(
        snapshot: CoordinatorSnapshot? = nil,
        message: String
    ) {
        ApplicationStartupFailurePresentation.apply(
            snapshot: snapshot,
            message: message,
            to: model
        ) {
            statusItemController?.refreshGatewayActivity()
            statusItemController?.refreshIcon()
        }
    }

    func startupErrorMessage(for error: any Swift.Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        // AsyncHTTPClient failures carry no localized description: without
        // this they read as "(AsyncHTTPClient.HTTPClientError error 1.)".
        if let connection = ProviderConnectionFailure.message(for: error) {
            return connection
        }
        return error.localizedDescription
    }

    func confirm(_ message: String, actionTitle: String = L10n.string("Continue")) -> Bool {
        // LittleSwitch runs as an accessory: a modal raised while the app is
        // not active returns immediately without ever appearing, which reads as
        // the user cancelling something they were never asked about.
        NSApp.activate(ignoringOtherApps: true)
        let alert = ApplicationConfirmationAlert.make(
            message: message,
            actionTitle: actionTitle,
            cancelTitle: L10n.string("Cancel")
        )
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Appends what a destructive step would throw away, so the question names
    /// the cost instead of leaving the user to remember it.
    func confirmDiscardingPendingChanges(_ message: String, actionTitle: String) -> Bool {
        guard let warning = model.pendingChangesWarning else {
            return confirm(message, actionTitle: actionTitle)
        }
        return confirm(L10n.string("\(message) \(warning)"), actionTitle: actionTitle)
    }
}
