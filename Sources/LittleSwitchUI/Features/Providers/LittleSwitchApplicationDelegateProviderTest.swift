import Foundation
import LittleSwitchCore

extension LittleSwitchApplicationDelegate {
    /// Runs the editor's Test and maps the failure to the stage it belongs
    /// to, so the sheet can report the script and the endpoint separately.
    func testProvider(_ input: ProviderInput) async -> ProviderTestOutcome {
        guard let coordinator else {
            return .authenticationFailed(
                L10n.string("LittleSwitch is still starting up. Try again in a moment.")
            )
        }
        do {
            return .passed(scriptOutput: try await coordinator.testProvider(input))
        } catch let error as CredentialScriptError {
            return .scriptFailed(startupErrorMessage(for: error))
        } catch {
            let isMissingScript = (error as? ApplicationCoordinator.Error) == .missingCredentialScript
            return isMissingScript
                ? .scriptFailed(startupErrorMessage(for: error))
                : .authenticationFailed(startupErrorMessage(for: error))
        }
    }
}
