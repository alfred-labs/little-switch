import Foundation
import LittleSwitchCore

package struct ProviderRefreshOperation: Sendable {
    package let token: UUID
    package let task: Task<CoordinatorSnapshot, any Swift.Error>
}

extension ApplicationCoordinator {
    public func saveProvider(_ input: ProviderInput) async throws -> CoordinatorSnapshot {
        guard Provider.maximumParallelRequestsRange.contains(input.maximumParallelRequests) else {
            throw Error.invalidMaximumParallelRequests
        }
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw Error.invalidProviderName
        }
        let normalizedURL = try ProviderEndpoint.normalize(input.baseURL)
        let providerID = input.id ?? UUID()
        let mutationSource = try providerMutationSource(input, providerID: providerID)
        let intent = beginProviderIntent(providerID: providerID)
        defer { finishProviderIntent(intent, providerID: providerID) }
        cancelProviderRefreshOperation(providerID: providerID)
        try validateProviderName(name, providerID: providerID)
        let previousProvider = configuration.providers.first { $0.id == providerID }
        let previousSecret = try secretStore.read(providerID: providerID)
        let reusableSecret = try reusableProviderCredential(input, previousSecret: previousSecret)
        let (credential, resolvedScript) = try await resolvedScriptCredential(
            input,
            previousProvider: mutationSource,
            previousSecret: reusableSecret,
            providerID: providerID
        )
        let credentialChanged = previousSecret != credential.secret
        var provider = Provider(
            id: providerID,
            name: name,
            baseURL: normalizedURL,
            authMode: input.authMode,
            credentialSource: input.credentialSource,
            credentialScriptPath: input.credentialSource == .script ? resolvedScript : nil,
            credentialRefreshInterval: input.credentialRefreshInterval,
            status: .refreshing,
            maximumParallelRequests: input.maximumParallelRequests,
            imageInputOverride: input.imageInputOverride,
            disabledThinkingOverride: input.disabledThinkingOverride,
            responsesWireOverride: input.responsesWireOverride,
            anthropicBaseURL: input.anthropicBaseURL
        )
        // The probe reads only baseURL/authMode/secret — none of discovery's
        // output — so it runs concurrently with model discovery and hides
        // under its round-trips instead of extending the save. An immutable
        // copy keeps the concurrent probe clear of the later model writes.
        let probeTarget = provider
        async let wireProbe = wireProbeForSave(
            provider: probeTarget,
            previous: previousProvider,
            credentialChanged: credentialChanged,
            secret: credential.secret
        )
        provider.models = try await providerClient.discover(
            provider: provider,
            secret: credential.secret
        )
        try requireCurrentProviderIntent(intent, providerID: providerID)
        try validateProviderName(name, providerID: providerID)
        provider.models = try discoveredModels(
            provider: provider,
            input: input,
            previousProvider: previousProvider
        )
        provider.lastRefresh = Date()
        provider.status = .ready
        provider.wireProbe = try await wireProbe
        // The namespace probe runs a real (tiny) generation, so it needs a
        // discovered model and rides after discovery instead of hiding
        // under it. A skipped probe is nil: not probed, not unknown.
        provider.namespaceProbe = try await namespaceProbeForSave(
            provider: provider,
            previous: previousProvider,
            credentialChanged: credentialChanged,
            secret: credential.secret,
            wireProbe: provider.wireProbe
        )

        let routingMutationToken = try await beginValidatedRoutingMutation(
            intent: intent,
            providerID: providerID,
            input: input,
            name: name,
            resolvedSecret: credential.secret
        )
        try await commitProvider(
            provider,
            credential: credential,
            previousSecret: previousSecret,
            dropsLegacyScript: previousProvider?.credentialSource == .script && input.credentialSource != .script,
            routingMutationToken: routingMutationToken
        )
        await seedResponsesCapability(from: provider.wireProbe, providerID: provider.id)
        let credentialChangedProviderIDs: Set<UUID> = credentialChanged ? [provider.id] : []
        await replaceGatewayRoutingIfNeeded(
            credentialChangedProviderIDs: credentialChangedProviderIDs
        )
        await refreshCredentialSchedule(
            providerID: providerID,
            credentialSource: input.credentialSource,
            interval: input.credentialRefreshInterval
        )
        if providerIntentIsCurrent(intent, providerID: providerID) {
            await gatewayRoutingMutationGuard.endAll(providerID: providerID)
        } else {
            await gatewayRoutingMutationGuard.end(routingMutationToken)
        }
        return await snapshot()
    }

    /// Acquires the routing mutation token, then re-checks every save
    /// invariant under it — intent currency, mutation source, name, and
    /// credential reuse. Any failure releases the token before throwing.
    private func beginValidatedRoutingMutation(
        intent: UInt64,
        providerID: UUID,
        input: ProviderInput,
        name: String,
        resolvedSecret: String?
    ) async throws -> UUID {
        let routingMutationToken = await gatewayRoutingMutationGuard.begin(providerID: providerID)
        do {
            try requireCurrentProviderIntent(intent, providerID: providerID)
            _ = try providerMutationSource(input, providerID: providerID)
            try validateProviderName(name, providerID: providerID)
            try validateProviderCredentialReuse(input, resolvedSecret: resolvedSecret)
        } catch {
            await gatewayRoutingMutationGuard.end(routingMutationToken)
            throw error
        }
        return routingMutationToken
    }

    /// Swaps the provider into the configuration and persists it; any
    /// failure rolls configuration and credential back together so a failed
    /// save leaves no half-applied state behind.
    private func commitProvider(
        _ provider: Provider,
        credential: ResolvedCredential,
        previousSecret: String?,
        dropsLegacyScript: Bool,
        routingMutationToken: UUID
    ) async throws {
        let oldConfiguration = configuration
        if let index = configuration.providers.firstIndex(where: { $0.id == provider.id }) {
            configuration.providers[index] = provider
        } else {
            configuration.providers.append(provider)
        }
        removeInvalidMappings(for: provider)
        do {
            try persistCredential(credential, providerID: provider.id)
            try configurationStore.save(configuration)
        } catch {
            configuration = oldConfiguration
            try restoreAfterFailedProviderSave(
                providerID: provider.id,
                previousSecret: previousSecret
            )
            await gatewayRoutingMutationGuard.end(routingMutationToken)
            throw error
        }
        if dropsLegacyScript {
            deleteLegacyCredentialScript(providerID: provider.id)
        }
    }

    /// Rolls the stored credential back after a failed save; any restore
    /// failure outweighs the persistence error that caused it. The script
    /// needs no rollback of its own: it lives on the provider row, which
    /// `configuration = oldConfiguration` already restored.
    private func restoreAfterFailedProviderSave(
        providerID: UUID,
        previousSecret: String?
    ) throws {
        do {
            try restoreCredential(previousSecret, providerID: providerID)
        } catch {
            throw Error.rollbackFailed
        }
    }

    public func refreshProvider(id: UUID) async throws -> CoordinatorSnapshot {
        if let operation = providerRefreshOperations[id] {
            return try await operation.task.value
        }
        let intent = beginProviderIntent(providerID: id)
        let operationToken = UUID()
        let task = Task<CoordinatorSnapshot, any Swift.Error> { [self] in
            defer {
                finishProviderRefreshOperation(
                    operationToken,
                    providerID: id
                )
            }
            return try await performProviderRefresh(id: id, intent: intent)
        }
        providerRefreshOperations[id] = ProviderRefreshOperation(
            token: operationToken,
            task: task
        )
        return try await task.value
    }

    private func performProviderRefresh(
        id: UUID,
        intent: UInt64
    ) async throws -> CoordinatorSnapshot {
        defer { finishProviderIntent(intent, providerID: id) }
        try Task.checkCancellation()
        guard let index = configuration.providers.firstIndex(where: { $0.id == id }) else {
            throw Error.invalidMapping
        }
        let secret = try secretStore.read(providerID: id)
        var provider = configuration.providers[index]
        provider.status = .refreshing
        configuration.providers[index] = provider
        do {
            let refreshedModels = try await providerClient.discover(
                provider: provider,
                secret: secret
            )
            try requireCurrentProviderIntent(intent, providerID: id)
            guard let refreshedIndex = configuration.providers.firstIndex(where: { $0.id == id })
            else {
                throw Error.providerMutationSuperseded
            }
            provider = configuration.providers[refreshedIndex]
            provider.models = try applyingContextOverrides(
                existingContextOverrides(provider),
                to: refreshedModels
            )
            provider.lastRefresh = Date()
            provider.status = .ready
            provider.lastError = nil
            configuration.providers[refreshedIndex] = provider
            removeInvalidMappings(for: provider)
            try configurationStore.save(configuration)
            await replaceGatewayRoutingIfNeeded()
            return await snapshot()
        } catch {
            let providerStillExists = configuration.providers.contains { $0.id == id }
            if !providerIntentIsCurrent(intent, providerID: id) || !providerStillExists {
                throw Error.providerMutationSuperseded
            }
            let failure = error
            let failureIndex = configuration.providers.firstIndex { $0.id == id }
                .unsafelyUnwrapped
            provider = configuration.providers[failureIndex]
            provider.status = .unavailable
            provider.lastError = "Model discovery failed"
            configuration.providers[failureIndex] = provider
            try? configurationStore.save(configuration)
            throw failure
        }
    }

    public func deleteProvider(id: UUID) async throws -> CoordinatorSnapshot {
        let intent = beginProviderIntent(providerID: id)
        defer { finishProviderIntent(intent, providerID: id) }
        cancelProviderRefreshOperation(providerID: id)
        let oldConfiguration = configuration
        let oldSecret = try secretStore.read(providerID: id)
        await credentialRefresher.cancel(providerID: id)
        let routingMutationToken = await gatewayRoutingMutationGuard.begin(providerID: id)
        do {
            try requireCurrentProviderIntent(intent, providerID: id)
        } catch {
            await gatewayRoutingMutationGuard.end(routingMutationToken)
            let survivor = configuration.providers.first { $0.id == id }
            await refreshCredentialSchedule(
                providerID: id,
                credentialSource: survivor?.credentialSource ?? .manual,
                interval: survivor?.credentialRefreshInterval
            )
            throw error
        }
        configuration.providers.removeAll { $0.id == id }
        configuration.mappings = configuration.mappings.filter { $0.value.providerID != id }
        configuration.codex = configuration.codex.normalized(for: configuration.providers)
        normalizeClaudeCodeConfiguration()
        normalizeOpenCodeConfiguration()
        do {
            try secretStore.delete(providerID: id)
            try secretStore.deleteScript(providerID: id)
            try configurationStore.save(configuration)
        } catch {
            let persistenceError = error
            configuration = oldConfiguration
            try restoreAfterFailedProviderSave(
                providerID: id,
                previousSecret: oldSecret
            )
            // The provider survived with its refresh loop cancelled and its
            // tombstone set; leave it running as it was or its token goes
            // stale with no badge until the next save or relaunch.
            let survivor = configuration.providers.first { $0.id == id }
            await refreshCredentialSchedule(
                providerID: id,
                credentialSource: survivor?.credentialSource ?? .manual,
                interval: survivor?.credentialRefreshInterval
            )
            await gatewayRoutingMutationGuard.end(routingMutationToken)
            throw persistenceError
        }
        await replaceGatewayRoutingIfNeeded()
        if providerIntentIsCurrent(intent, providerID: id) {
            await gatewayRoutingMutationGuard.endAll(providerID: id)
        } else {
            await gatewayRoutingMutationGuard.end(routingMutationToken)
        }
        return await snapshot()
    }

    /// While connected, mapping edits wait in the draft until Apply commits
    /// them in one persist + one gateway routing swap; disconnected edits
    /// write through immediately, since nothing serves traffic yet.
    public func setMapping(
        routeID: String,
        mapping: ModelMapping?
    ) async throws -> CoordinatorSnapshot {
        guard ClaudeRoute.all.contains(where: { $0.id == routeID }) else {
            throw Error.invalidMapping
        }
        if let mapping {
            guard
                configuration.providers.contains(where: { provider in
                    provider.id == mapping.providerID
                        && provider.models.contains(where: { $0.id == mapping.modelID })
                })
            else {
                throw Error.invalidMapping
            }
        }
        guard configuration.connected else {
            return try await writeMapping(routeID: routeID, mapping: mapping)
        }
        updateClaudeMappingsDraft { draft in
            draft[routeID] = mapping
        }
        return await snapshot()
    }

    private func writeMapping(
        routeID: String,
        mapping: ModelMapping?
    ) async throws -> CoordinatorSnapshot {
        // Normalization must run before the save it ships with, so this
        // setter keeps its own persist-rollback instead of the shared helper.
        let oldConfiguration = configuration
        if let mapping {
            configuration.mappings[routeID] = mapping
        } else {
            configuration.mappings.removeValue(forKey: routeID)
        }
        normalizeClaudeCodeConfiguration()
        do {
            try configurationStore.save(configuration)
        } catch {
            configuration = oldConfiguration
            throw error
        }
        await replaceGatewayRoutingIfNeeded()
        return await snapshot()
    }

    /// Auto mode is the only mapping-independent setting carried by the
    /// Claude Desktop profile, so applying it live means rewriting the
    /// profile and relaunching Desktop to pick the new value up.
    public func setAutoMode(_ enabled: Bool) async throws -> CoordinatorSnapshot {
        let previous = try await persistingConfigurationChange {
            $0.autoMode = enabled
        }
        guard configuration.connected else {
            return await snapshot()
        }
        let tlsReady = tlsProvisioner.map { $0.isTrusted(secretStore: secretStore) } ?? false
        do { try profileManager.activate(autoMode: enabled, tlsEnabled: tlsReady) } catch {
            configuration = previous
            do {
                try configurationStore.save(previous)
            } catch {
                throw Error.rollbackFailed
            }
            throw error
        }
        if await claudeController.relaunch() == .failed {
            throw Error.relaunchFailed
        }
        return await snapshot()
    }

    /// The catalog indicator is a presentation preference: persist it and
    /// hot-swap the gateway catalog, nothing else to touch. Deliberately
    /// unguarded — re-applying the current value also repairs a gateway
    /// whose indicator has drifted.
    public func setModelIndicator(
        _ indicator: ModelIndicator
    ) async throws -> CoordinatorSnapshot {
        try await persistingConfigurationChange {
            $0.modelIndicator = indicator
        }
        await replaceGatewayRoutingIfNeeded()
        return await snapshot()
    }

    /// Persists a configuration mutation with in-memory rollback; returns the
    /// configuration as it was, for callers with further committed layers to
    /// unwind.
    @discardableResult
    private func persistingConfigurationChange(
        _ change: (inout AppConfiguration) -> Void
    ) async throws -> AppConfiguration {
        let oldConfiguration = configuration
        change(&configuration)
        do {
            try configurationStore.save(configuration)
        } catch {
            configuration = oldConfiguration
            throw error
        }
        return oldConfiguration
    }

    private func beginProviderIntent(providerID: UUID) -> UInt64 {
        providerIntentGeneration &+= 1
        providerIntents[providerID] = providerIntentGeneration
        return providerIntentGeneration
    }

    private func providerIntentIsCurrent(_ intent: UInt64, providerID: UUID) -> Bool {
        providerIntents[providerID] == intent
    }

    private func finishProviderIntent(_ intent: UInt64, providerID: UUID) {
        if providerIntentIsCurrent(intent, providerID: providerID) {
            providerIntents[providerID] = nil
        }
    }

    private func requireCurrentProviderIntent(_ intent: UInt64, providerID: UUID) throws {
        guard providerIntentIsCurrent(intent, providerID: providerID) else {
            throw Error.providerMutationSuperseded
        }
    }

    private func cancelProviderRefreshOperation(providerID: UUID) {
        providerRefreshOperations.removeValue(forKey: providerID)?.task.cancel()
    }

    private func finishProviderRefreshOperation(
        _ token: UUID,
        providerID: UUID
    ) {
        guard providerRefreshOperations[providerID]?.token == token else {
            return
        }
        providerRefreshOperations[providerID] = nil
    }

    private func validateProviderName(_ name: String, providerID: UUID) throws {
        guard ProviderNameValidation.message(name, providers: configuration.providers, excluding: providerID) == nil
        else {
            throw Error.duplicateProviderName
        }
    }

    private func removeInvalidMappings(for provider: Provider) {
        let modelIDs = Set(provider.models.map(\.id))
        configuration.mappings = configuration.mappings.filter { _, mapping in
            mapping.providerID != provider.id || modelIDs.contains(mapping.modelID)
        }
        configuration.codex = configuration.codex.normalized(for: configuration.providers)
        normalizeClaudeCodeConfiguration()
        normalizeOpenCodeConfiguration()
    }
}
