import Foundation
import LittleSwitchCore

extension ApplicationCoordinator {
    /// Creation and duplication never upsert: their identity must remain
    /// unclaimed through every suspension until the synchronous commit.
    package func providerMutationSource(_ input: ProviderInput, providerID: UUID) throws -> Provider? {
        let destination = configuration.providers.first { $0.id == providerID }
        switch input.intent {
        case .add:
            guard destination == nil else {
                throw Error.providerMutationSuperseded
            }
            return nil
        case .edit:
            guard let destination else {
                throw Error.providerMutationSuperseded
            }
            return destination
        case .duplicate(let sourceID):
            guard input.id != nil, sourceID != providerID, destination == nil else {
                throw Error.providerMutationSuperseded
            }
            guard let source = configuration.providers.first(where: { $0.id == sourceID }) else {
                throw Error.providerDuplicationSourceUnavailable
            }
            return source
        }
    }

    /// A duplicate's presentation contains only its source UUID. Resolve a
    /// reusable manual key here and keep it inside the coordinator transaction.
    package func reusableProviderCredential(
        _ input: ProviderInput,
        previousSecret: String?
    ) throws -> String? {
        guard case .duplicate(let sourceID) = input.intent,
            input.authMode != .none,
            input.credentialSource == .manual,
            (input.credential ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return previousSecret
        }
        guard configuration.providers.first(where: { $0.id == sourceID })?.credentialSource == .manual,
            let secret = try secretStore.read(providerID: sourceID),
            !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw Error.missingOriginalProviderCredential
        }
        return secret
    }

    /// A deleted or rotated source key must not be resurrected by a save that
    /// was suspended in discovery. A newly typed key is independent of it.
    package func validateProviderCredentialReuse(
        _ input: ProviderInput,
        resolvedSecret: String?
    ) throws {
        guard case .duplicate = input.intent else { return }
        let current = try reusableProviderCredential(input, previousSecret: resolvedSecret)
        guard current == resolvedSecret else {
            throw Error.providerMutationSuperseded
        }
    }
}
