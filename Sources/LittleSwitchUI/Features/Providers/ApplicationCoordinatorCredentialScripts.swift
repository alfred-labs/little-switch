import Foundation
import LittleSwitchCore

/// Credential plumbing for `ApplicationCoordinator`: resolving what a save
/// should store, persisting and rolling back secrets, and keeping the script
/// refresh schedule in step with each provider's authentication mode.
extension ApplicationCoordinator {
    /// What a save resolved to: the in-memory secret used for this refresh and
    /// how it should land in the keychain.
    package struct ResolvedCredential {
        enum Persistence {
            case delete
            case write(String)
        }

        let secret: String?
        let persistence: Persistence
    }

    /// Resolves the credential for an incoming provider save. Script mode runs
    /// the chosen script once here, so the produced token is what gets stored
    /// and the editor surfaces any script failure before anything is persisted.
    package func resolvedScriptCredential(
        _ input: ProviderInput,
        previousProvider: Provider?,
        previousSecret: String?,
        providerID: UUID
    ) async throws -> (credential: ResolvedCredential, scriptPath: String) {
        guard input.credentialSource == .script else {
            let credential = try resolvedCredential(
                input.credential,
                authMode: input.authMode,
                previous: previousSecret
            )
            return (credential, "")
        }
        let scriptPath = try resolvedCredentialScriptPath(
            input.scriptPath,
            previousProvider: previousProvider
        )
        do {
            let run = try await credentialScriptRunner.run(scriptPath: scriptPath)
            await recordScriptOutcome(
                providerID: providerID,
                CredentialRefreshOutcome(
                    kind: .refreshed,
                    standardError: run.standardError
                )
            )
            return (
                ResolvedCredential(secret: run.token, persistence: .write(run.token)),
                scriptPath
            )
        } catch {
            await recordScriptOutcome(providerID: providerID, .failure(from: error))
            throw error
        }
    }

    package func resolvedCredential(
        _ proposed: String?,
        authMode: AuthMode,
        previous: String?
    ) throws -> ResolvedCredential {
        if authMode == .none {
            return ResolvedCredential(secret: nil, persistence: .delete)
        }
        if let proposed, !proposed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ResolvedCredential(secret: proposed, persistence: .write(proposed))
        }
        if let previous, !previous.isEmpty {
            return ResolvedCredential(secret: previous, persistence: .write(previous))
        }
        return ResolvedCredential(secret: nil, persistence: .delete)
    }

    /// Script authentication runs the user's chosen script file itself; the
    /// credential field is unused and a blank path keeps the configured one,
    /// which lives on the provider row.
    package func resolvedCredentialScriptPath(
        _ proposed: String?,
        previousProvider: Provider?
    ) throws -> String {
        if let proposed, !proposed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return proposed
        }
        let previous =
            previousProvider?.credentialScriptPath?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !previous.isEmpty else {
            throw Error.missingCredentialScript
        }
        return previous
    }

    /// Records a test or save script run — its stderr feeds the editor's
    /// output pane, and a failure keeps the provider-list badge until the
    /// next successful run clears it.
    package func recordScriptOutcome(
        providerID: UUID,
        _ outcome: CredentialRefreshOutcome
    ) async {
        await credentialRefresher.record(providerID: providerID, outcome: outcome)
    }

    /// Runs the checks a save would run and reports what they produced,
    /// without persisting anything: the editor's Test gate before Save
    /// unlocks. Script mode runs the chosen file and then probes the
    /// endpoint with the token it produced, so a script that prints garbage
    /// cannot pass on its own.
    public func testProvider(_ input: ProviderInput) async throws -> String? {
        let providerID = input.id ?? UUID()
        let mutationSource = try providerMutationSource(input, providerID: providerID)
        guard input.credentialSource == .script else {
            let previousSecret =
                input.intent == .edit
                ? try secretStore.read(providerID: providerID)
                : nil
            let credential = try resolvedCredential(
                input.credential,
                authMode: input.authMode,
                previous: reusableProviderCredential(input, previousSecret: previousSecret)
            )
            let provider = Provider(
                id: providerID,
                name: input.name,
                baseURL: input.baseURL,
                authMode: input.authMode,
                anthropicBaseURL: input.anthropicBaseURL
            )
            _ = try await providerClient.discover(
                provider: provider,
                secret: credential.secret
            )
            _ = try providerMutationSource(input, providerID: providerID)
            try validateProviderCredentialReuse(input, resolvedSecret: credential.secret)
            return nil
        }
        let scriptPath = try resolvedCredentialScriptPath(
            input.scriptPath,
            previousProvider: mutationSource
        )
        let run: CredentialScriptRun
        do {
            run = try await credentialScriptRunner.run(scriptPath: scriptPath)
        } catch {
            await recordScriptOutcome(
                providerID: providerID,
                .failure(from: error)
            )
            throw error
        }
        await recordScriptOutcome(
            providerID: providerID,
            CredentialRefreshOutcome(
                kind: .refreshed,
                standardError: run.standardError
            )
        )
        let provider = Provider(
            id: providerID,
            name: input.name,
            baseURL: input.baseURL,
            authMode: input.authMode,
            anthropicBaseURL: input.anthropicBaseURL
        )
        _ = try await providerClient.discover(
            provider: provider,
            secret: run.token
        )
        _ = try providerMutationSource(input, providerID: providerID)
        return run.standardError.isEmpty ? nil : run.standardError
    }

    package func persistCredential(
        _ credential: ResolvedCredential,
        providerID: UUID
    ) throws {
        switch credential.persistence {
        case .delete:
            try secretStore.delete(providerID: providerID)
        case .write(let secret):
            try secretStore.write(secret, providerID: providerID)
        }
    }

    /// Retires a script left in the keychain by pre-0.1.5 versions once the
    /// provider no longer uses script authentication.
    package func deleteLegacyCredentialScript(providerID: UUID) {
        try? secretStore.deleteScript(providerID: providerID)
    }

    package func restoreCredential(_ secret: String?, providerID: UUID) throws {
        if let secret {
            try secretStore.write(secret, providerID: providerID)
        } else {
            try secretStore.delete(providerID: providerID)
        }
    }

    /// Script credentials refresh on their own cadence; every other source
    /// has no scheduled work, so any previous loop is stopped.
    package func refreshCredentialSchedule(
        providerID: UUID,
        credentialSource: CredentialSource,
        interval: TimeInterval?
    ) async {
        await credentialRefresher.cancel(providerID: providerID)
        guard credentialSource == .script else {
            return
        }
        let scriptPath =
            configuration.providers.first { $0.id == providerID }?.credentialScriptPath
            ?? ""
        await credentialRefresher.schedule(
            providerID: providerID,
            interval: interval ?? Provider.defaultCredentialRefreshInterval,
            immediate: false,
            scriptPath: scriptPath
        )
    }
}
