import Foundation
import LittleSwitchCommon

extension CredentialRefreshOutcome {
    /// The failure outcome for a thrown error: the user-facing localized
    /// text when the error carries one, its plain description otherwise.
    /// The save flow and the refresh loop must render the same failure the
    /// same way — both build their badge through this factory.
    public static func failure(from error: any Error) -> Self {
        Self(
            kind: .failed,
            message: (error as? LocalizedError)?.errorDescription
                ?? String(describing: error),
            standardError: (error as? CredentialScriptError)?.standardError ?? ""
        )
    }
}
