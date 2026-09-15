import Foundation
import LittleSwitchCommon
import LittleSwitchSearch

public struct GatewayRoutingCapture: Equatable, Sendable {
    public let snapshot: RoutingSnapshot
    private let providerRevisions: [UUID: UInt64]

    package init(snapshot: RoutingSnapshot, providerRevisions: [UUID: UInt64]) {
        self.snapshot = snapshot
        self.providerRevisions = providerRevisions
    }

    public func providerRevision(for providerID: UUID) -> UInt64? {
        providerRevisions[providerID]
    }
}

package struct GatewayRequestAdmission: Sendable {
    package let eventID: UUID
    package let capture: GatewayRoutingCapture
    package let client: GatewayClient
    package let modelIdentifier: String
    package let providerID: UUID
    package let targetModelID: String
    package let retainedBodyBytes: Int

    package init(
        eventID: UUID,
        capture: GatewayRoutingCapture,
        client: GatewayClient,
        modelIdentifier: String,
        providerID: UUID,
        targetModelID: String,
        retainedBodyBytes: Int
    ) {
        self.eventID = eventID
        self.capture = capture
        self.client = client
        self.modelIdentifier = modelIdentifier
        self.providerID = providerID
        self.targetModelID = targetModelID
        self.retainedBodyBytes = retainedBodyBytes
    }
}

package actor GatewayRoutingMutationGuard {
    private var providerByToken: [UUID: UUID] = [:]

    package init() {}

    package func begin(providerID: UUID) -> UUID {
        let token = UUID()
        providerByToken[token] = providerID
        return token
    }

    package func end(_ token: UUID) {
        providerByToken[token] = nil
    }

    package func endAll(providerID: UUID) {
        providerByToken = providerByToken.filter { $0.value != providerID }
    }

    package func readCredential(
        providerID: UUID,
        secretStore: any SecretStore
    ) throws -> String? {
        guard !providerByToken.values.contains(providerID) else {
            throw GatewayAdmissionError.invalidated
        }
        return try secretStore.read(providerID: providerID)
    }
}

public actor GatewayState {
    public enum Error: Swift.Error, Equatable {
        case notAcceptingRequests
    }

    private var snapshot: RoutingSnapshot
    private var requestCount = 0
    private var claudeRequestCount = 0
    private var codexRequestCount = 0
    private var acceptingRequests = true
    private var providerRevisions: [UUID: UInt64]
    package nonisolated let routingMutationGuard: GatewayRoutingMutationGuard
    /// Learned per-provider Responses capability. Lives on the state, not the
    /// responder, so verdicts survive gateway restarts and stay readable by
    /// the UI while the server runs.
    nonisolated public let responsesCapabilities: ResponsesCapabilityLedger
    package nonisolated let imageInputRegistry: ModelImageInputRegistry?
    package nonisolated let customToolCapabilities: CustomToolCapabilityCache?
    private let requestPool: any ProviderRequestPooling
    private var requestPoolReconfigurationTask: Task<Void, Never>?
    private var requestPoolReconfigurationGeneration: UInt64 = 0
    /// Last configuration actually pushed to the request pool. Replaces that
    /// produce an identical configuration (e.g. a display-only indicator
    /// change) swap the snapshot without touching the pool, so admissions
    /// never wait behind a no-op reconfiguration.
    private var appliedPoolConfiguration: ProviderRequestPoolConfiguration?

    public init(snapshot: RoutingSnapshot) {
        self.init(snapshot: snapshot, routingMutationGuard: GatewayRoutingMutationGuard())
    }

    package init(
        snapshot: RoutingSnapshot,
        routingMutationGuard: GatewayRoutingMutationGuard
    ) {
        self.init(
            snapshot: snapshot,
            routingMutationGuard: routingMutationGuard,
            responsesCapabilities: ResponsesCapabilityLedger()
        )
    }

    package init(
        snapshot: RoutingSnapshot,
        requestPool: (any ProviderRequestPooling)? = nil,
        routingMutationGuard: GatewayRoutingMutationGuard = GatewayRoutingMutationGuard(),
        responsesCapabilities: ResponsesCapabilityLedger = ResponsesCapabilityLedger(),
        imageInputRegistry: ModelImageInputRegistry? = nil,
        customToolCapabilities: CustomToolCapabilityCache? = nil
    ) {
        self.snapshot = snapshot
        let revisions = Dictionary(
            uniqueKeysWithValues: snapshot.providers.map { ($0.id, UInt64(0)) })
        providerRevisions = revisions
        self.routingMutationGuard = routingMutationGuard
        self.responsesCapabilities = responsesCapabilities
        self.imageInputRegistry = imageInputRegistry
        self.customToolCapabilities = customToolCapabilities
        let initial = snapshot.providerRequestPoolConfiguration(providerRevisions: revisions)
        self.requestPool = requestPool ?? ProviderRequestPool(configuration: initial)
        appliedPoolConfiguration = requestPool == nil ? initial : nil
    }

    public var sessionRequestCount: Int {
        requestCount
    }

    public var claudeSessionRequestCount: Int {
        claudeRequestCount
    }

    public var codexSessionRequestCount: Int {
        codexRequestCount
    }

    public func capture() -> RoutingSnapshot {
        snapshot
    }

    public func routingCapture() -> GatewayRoutingCapture {
        GatewayRoutingCapture(
            snapshot: snapshot,
            providerRevisions: providerRevisions
        )
    }

    package func requireCustomToolRevision(_ revision: UInt64, providerID: UUID) throws {
        guard providerRevisions[providerID] == revision else { throw GatewayAdmissionError.invalidated }
    }

    package func providerCredential(
        providerID: UUID,
        capture: GatewayRoutingCapture,
        secretStore: any SecretStore
    ) async throws -> String? {
        let credential = try await routingMutationGuard.readCredential(
            providerID: providerID,
            secretStore: secretStore
        )
        guard capture.providerRevision(for: providerID) == providerRevisions[providerID] else {
            throw GatewayAdmissionError.invalidated
        }
        return credential
    }

    @discardableResult
    public func replace(
        providers: [Provider],
        mappings: [String: ModelMapping],
        codex: CodexConfiguration? = nil,
        webSearch: WebSearchConfiguration? = nil,
        modelIndicator: ModelIndicator? = nil,
        credentialChangedProviderIDs: Set<UUID> = []
    ) async -> RoutingSnapshot {
        let revisions = updatedProviderRevisions(
            for: providers,
            credentialChangedProviderIDs: credentialChangedProviderIDs
        )
        let replacement = RoutingSnapshot(
            generation: snapshot.generation &+ 1,
            providers: providers,
            mappings: mappings,
            codex: codex ?? snapshot.codex,
            webSearch: webSearch ?? snapshot.webSearch,
            modelIndicator: modelIndicator ?? snapshot.modelIndicator
        )
        let changedProviders = Set(providerRevisions.keys).union(revisions.keys).filter {
            providerRevisions[$0] != revisions[$0]
        }
        snapshot = replacement
        providerRevisions = revisions

        let requestPool = self.requestPool
        let configuration = replacement.providerRequestPoolConfiguration(
            providerRevisions: revisions
        )
        if configuration == appliedPoolConfiguration, requestPoolReconfigurationTask == nil {
            appliedPoolConfiguration = configuration
            if !changedProviders.isEmpty {
                await customToolCapabilities?.invalidate(providerIDs: Set(changedProviders))
            }
            return replacement
        }
        appliedPoolConfiguration = configuration
        let previousTask = requestPoolReconfigurationTask
        requestPoolReconfigurationGeneration &+= 1
        let reconfigurationGeneration = requestPoolReconfigurationGeneration
        let customToolCapabilities = self.customToolCapabilities
        let reconfigurationTask = Task {
            await previousTask?.value
            if !changedProviders.isEmpty {
                await customToolCapabilities?.invalidate(providerIDs: Set(changedProviders))
            }
            await requestPool.reconfigure(configuration)
        }
        requestPoolReconfigurationTask = reconfigurationTask
        await reconfigurationTask.value
        if requestPoolReconfigurationGeneration == reconfigurationGeneration {
            requestPoolReconfigurationTask = nil
        }
        return replacement
    }

    public func admit(client: GatewayClient = .claude) throws {
        guard acceptingRequests else {
            throw Error.notAcceptingRequests
        }
        requestCount += 1
        switch client {
        case .claude:
            claudeRequestCount += 1
        case .codex:
            codexRequestCount += 1
        }
    }

    package func admit(
        _ admission: GatewayRequestAdmission,
        onAwaitingReconfiguration: @Sendable () async -> Void = {}
    ) async throws {
        guard acceptingRequests else {
            throw Error.notAcceptingRequests
        }
        let reconfigurationTask = requestPoolReconfigurationTask
        await onAwaitingReconfiguration()
        await reconfigurationTask?.value
        guard acceptingRequests else {
            throw Error.notAcceptingRequests
        }
        guard
            let providerRevision = admission.capture.providerRevision(
                for: admission.providerID
            )
        else {
            throw GatewayAdmissionError.invalidated
        }
        do {
            try await requestPool.admit(
                ProviderRequestAdmission(
                    eventID: admission.eventID,
                    providerID: admission.providerID,
                    providerRevision: providerRevision,
                    client: admission.client,
                    modelIdentifier: admission.modelIdentifier,
                    targetModelID: admission.targetModelID,
                    retainedBodyBytes: admission.retainedBodyBytes
                )
            )
        } catch GatewayAdmissionError.notAcceptingRequests {
            throw Error.notAcceptingRequests
        }
        guard acceptingRequests else {
            await requestPool.finish(eventID: admission.eventID)
            throw Error.notAcceptingRequests
        }

        requestCount += 1
        switch admission.client {
        case .claude:
            claudeRequestCount += 1
        case .codex:
            codexRequestCount += 1
        }
    }

    public func finish(eventID: UUID) async {
        await requestPool.finish(eventID: eventID)
    }

    /// Diagnostic work shares capacity and invalidation with traffic, but never increments conversation counters.
    package func admitImageProbe(eventID: UUID, provider: Provider, modelID: String) async throws {
        await requestPoolReconfigurationTask?.value
        guard acceptingRequests else { throw GatewayAdmissionError.notAcceptingRequests }
        guard let current = snapshot.providers.first(where: { $0.id == provider.id }),
            current.hasSameImageInputIdentity(as: provider),
            let revision = providerRevisions[provider.id]
        else { throw GatewayAdmissionError.invalidated }
        try await requestPool.admit(
            ProviderRequestAdmission(
                eventID: eventID,
                providerID: provider.id,
                providerRevision: revision,
                client: .codex,
                modelIdentifier: modelID,
                targetModelID: modelID,
                retainedBodyBytes: 16 * 1_024,
                purpose: .imageProbe))
        guard acceptingRequests, providerRevisions[provider.id] == revision else {
            await requestPool.finish(eventID: eventID)
            throw GatewayAdmissionError.invalidated
        }
    }

    public func requestPoolSnapshot() async -> ProviderRequestPoolSnapshot {
        var stableSnapshot: ProviderRequestPoolSnapshot?
        repeat {
            let generation = requestPoolReconfigurationGeneration
            let reconfigurationTask = requestPoolReconfigurationTask
            await reconfigurationTask?.value
            let poolSnapshot = await requestPool.snapshot()
            if generation == requestPoolReconfigurationGeneration {
                stableSnapshot = poolSnapshot
            }
        } while stableSnapshot == nil
        return stableSnapshot.unsafelyUnwrapped
    }

    /// Learned verdicts for every probed provider: true means its
    /// `/v1/responses` answered and native Responses traffic is served
    /// natively, false means the route was absent and the chat-completions
    /// adapter took over.
    public func responsesCapabilityVerdicts() async -> [UUID: Bool] {
        await responsesCapabilities.verdicts()
    }

    public func stopAdmissions() async {
        acceptingRequests = false
        let reconfigurationTask = requestPoolReconfigurationTask
        await reconfigurationTask?.value
        await requestPool.shutdown()
    }

    private func updatedProviderRevisions(
        for providers: [Provider],
        credentialChangedProviderIDs: Set<UUID>
    ) -> [UUID: UInt64] {
        let previousProviders = Dictionary(
            uniqueKeysWithValues: snapshot.providers.map { ($0.id, $0) }
        )
        let replacementIDs = Set(providers.map(\.id))
        var revisions = providerRevisions

        for previousProvider in snapshot.providers
        where !replacementIDs.contains(previousProvider.id) {
            let revision = revisions[previousProvider.id].unsafelyUnwrapped
            revisions[previousProvider.id] = revision &+ 1
        }

        for provider in providers {
            guard let previousProvider = previousProviders[provider.id] else {
                if revisions[provider.id] == nil {
                    revisions[provider.id] = 0
                } else {
                    let revision = revisions[provider.id].unsafelyUnwrapped
                    revisions[provider.id] = revision &+ 1
                }
                continue
            }
            let invalidatesCapture =
                !provider.hasSameImageInputIdentity(as: previousProvider)
                || credentialChangedProviderIDs.contains(provider.id)
            if invalidatesCapture {
                let revision = revisions[provider.id].unsafelyUnwrapped
                revisions[provider.id] = revision &+ 1
            }
        }
        return revisions
    }
}

public enum GatewaySecurity {
    public static func isAllowedAuthority(
        _ authority: String,
        requiredPort: Int? = 11_436
    ) -> Bool {
        let trimmed = authority.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let components = URLComponents(string: "http://\(trimmed)"),
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil,
            let host = components.host?.lowercased(),
            !host.isEmpty,
            requiredPort == nil || components.port == requiredPort
        else {
            return false
        }

        if host == "localhost" || host == "::1" || host == "[::1]" {
            return true
        }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4
            && octets.first == "127"
            && octets.allSatisfy { octet in
                guard let value = Int(octet) else { return false }
                return (0...255).contains(value)
            }
    }
}

package struct GatewayAuthorityPolicy: Sendable {
    private let requiredPort: Int?

    package init(_ requiredPort: Int?) {
        self.requiredPort = requiredPort
    }

    package func allows(_ authority: String) -> Bool {
        GatewaySecurity.isAllowedAuthority(
            authority,
            requiredPort: requiredPort
        )
    }
}
