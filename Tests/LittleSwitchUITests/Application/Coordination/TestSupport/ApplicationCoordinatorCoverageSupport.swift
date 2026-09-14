import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import LittleSwitchTransport
import NIOCore
import NIOHTTP1

@testable import LittleSwitchUI

final class ScriptedConfigurationStore: ConfigurationStoring, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case loadInjected
        case saveInjected
    }

    private let lock = NSLock()
    private var stored: AppConfiguration
    private var loadShouldFail = false
    private var saveAttempt = 0
    private var failingSaveAttempts: Set<Int> = []
    private var saveInputs: [AppConfiguration] = []

    init(configuration: AppConfiguration) {
        stored = configuration
    }

    var configuration: AppConfiguration {
        lock.withLock { stored }
    }

    var saves: [AppConfiguration] {
        lock.withLock { saveInputs }
    }

    func load() throws -> AppConfiguration {
        try lock.withLock {
            guard !loadShouldFail else { throw Error.loadInjected }
            return stored
        }
    }

    func save(_ configuration: AppConfiguration) throws {
        try lock.withLock {
            saveAttempt += 1
            guard !failingSaveAttempts.contains(saveAttempt) else {
                throw Error.saveInjected
            }
            stored = configuration
            saveInputs.append(configuration)
        }
    }

    func failLoad() {
        lock.withLock { loadShouldFail = true }
    }

    func failSaves(on attempts: Set<Int>) {
        lock.withLock { failingSaveAttempts = attempts }
    }

    func failFutureSaves(at offsets: Set<Int>) {
        lock.withLock {
            failingSaveAttempts = Set(offsets.map { saveAttempt + $0 })
        }
    }
}

final class ScriptedClaudeProfileManager: ClaudeProfileManaging, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case activateInjected
        case restoreInjected
        case statusInjected
    }

    private let lock = NSLock()
    private var active: Bool
    private var activationAttempt = 0
    private var restoreAttempt = 0
    private var failingActivationAttempts: Set<Int> = []
    private var failingRestoreAttempts: Set<Int> = []
    private var statusShouldFail = false

    init(active: Bool = false) {
        self.active = active
    }

    var activationCount: Int {
        lock.withLock { activationAttempt }
    }

    var restoreCount: Int {
        lock.withLock { restoreAttempt }
    }

    func activate(autoMode: Bool, tlsEnabled: Bool) throws {
        _ = autoMode
        try lock.withLock {
            activationAttempt += 1
            guard !failingActivationAttempts.contains(activationAttempt) else {
                throw Error.activateInjected
            }
            active = true
        }
    }

    func restore() throws {
        try lock.withLock {
            restoreAttempt += 1
            guard !failingRestoreAttempts.contains(restoreAttempt) else {
                throw Error.restoreInjected
            }
            active = false
        }
    }

    func isActive(autoMode: Bool) throws -> Bool {
        _ = autoMode
        return try lock.withLock {
            guard !statusShouldFail else { throw Error.statusInjected }
            return active
        }
    }

    func failActivations(on attempts: Set<Int>) {
        lock.withLock { failingActivationAttempts = attempts }
    }

    func failRestores(on attempts: Set<Int>) {
        lock.withLock { failingRestoreAttempts = attempts }
    }

    func failStatus() {
        lock.withLock { statusShouldFail = true }
    }
}

struct ScriptedCodexActivation: Equatable, Sendable {
    let providers: [Provider]
    let configuration: CodexConfiguration
}

final class ScriptedCodexProfileManager: CodexProfileManaging, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case activateInjected
        case restoreInjected
        case statusInjected
    }

    private let lock = NSLock()
    private var active: Bool
    private var legacyActive: Bool
    private var activationAttempt = 0
    private var restoreAttempt = 0
    private var failingActivationAttempts: Set<Int> = []
    private var failingRestoreAttempts: Set<Int> = []
    private var statusShouldFail = false
    private var activationInputs: [ScriptedCodexActivation] = []
    private var signatureInputs: [CodexManagedProfileSignature] = []

    init(active: Bool = false, legacyActiveWithoutConcurrency: Bool = false) {
        self.active = active
        legacyActive = legacyActiveWithoutConcurrency
    }

    var activations: [CodexConfiguration] {
        lock.withLock { activationInputs.map(\.configuration) }
    }

    var activationSnapshots: [ScriptedCodexActivation] {
        lock.withLock { activationInputs }
    }

    var signatures: [CodexManagedProfileSignature] {
        lock.withLock { signatureInputs }
    }

    var restoreCount: Int {
        lock.withLock { restoreAttempt }
    }

    func activate(providers: [Provider], configuration: CodexConfiguration) throws {
        let signature = try CodexManagedProfileSignature.resolve(
            providers: providers,
            configuration: configuration
        )
        try activate(
            providers: providers,
            configuration: configuration,
            signature: signature
        )
    }

    func activate(
        providers: [Provider],
        configuration: CodexConfiguration,
        signature: CodexManagedProfileSignature
    ) throws {
        try lock.withLock {
            activationAttempt += 1
            guard !failingActivationAttempts.contains(activationAttempt) else {
                throw Error.activateInjected
            }
            activationInputs.append(
                ScriptedCodexActivation(
                    providers: providers,
                    configuration: configuration
                )
            )
            signatureInputs.append(signature)
            active = true
            legacyActive = false
        }
    }

    func restore() throws {
        try lock.withLock {
            restoreAttempt += 1
            guard !failingRestoreAttempts.contains(restoreAttempt) else {
                throw Error.restoreInjected
            }
            active = false
            legacyActive = false
        }
    }

    func isActive(providers: [Provider], configuration: CodexConfiguration) throws -> Bool {
        _ = providers
        _ = configuration
        return try lock.withLock {
            guard !statusShouldFail else { throw Error.statusInjected }
            return active || legacyActive
        }
    }

    func status(
        providers: [Provider],
        configuration: CodexConfiguration,
        expected: CodexManagedProfileSignature
    ) throws -> CodexProfileStatus {
        _ = providers
        _ = configuration
        return try lock.withLock {
            guard !statusShouldFail else { throw Error.statusInjected }
            if legacyActive {
                return .requiresUpdate(expected.withoutNativeConcurrency())
            }
            return active ? .active(expected) : .inactive
        }
    }

    func failActivations(on attempts: Set<Int>) {
        lock.withLock { failingActivationAttempts = attempts }
    }

    func failRestores(on attempts: Set<Int>) {
        lock.withLock { failingRestoreAttempts = attempts }
    }

    func failStatus() {
        lock.withLock { statusShouldFail = true }
    }
}

@MainActor
// swiftlint:disable opening_brace
final class ScriptedApplicationController: ClaudeApplicationControlling,
    CodexApplicationControlling
{
    enum Error: Swift.Error, Equatable {
        case quitInjected
        case openInjected
    }

    private(set) var quitAttempts = 0
    private(set) var openAttempts = 0
    private var running: Bool
    private var failingQuitAttempts: Set<Int> = []
    private var failingOpenAttempts: Set<Int> = []

    init(running: Bool = false) {
        self.running = running
    }

    func isRunning() -> Bool { running }

    func quitAndWait() async throws {
        quitAttempts += 1
        guard !failingQuitAttempts.contains(quitAttempts) else {
            throw Error.quitInjected
        }
        running = false
    }

    func open() async throws {
        openAttempts += 1
        guard !failingOpenAttempts.contains(openAttempts) else {
            throw Error.openInjected
        }
        running = true
    }

    func failQuits(on attempts: Set<Int>) {
        failingQuitAttempts = attempts
    }

    func failOpens(on attempts: Set<Int>) {
        failingOpenAttempts = attempts
    }
}
// swiftlint:enable opening_brace

actor ScriptedCatalogTransport: UpstreamTransport {
    enum Error: Swift.Error, Equatable {
        case executeInjected
        case shutdownInjected
    }

    enum WaitError: Swift.Error, Equatable {
        case executeTimedOut(Int)
    }

    enum Execution: Sendable {
        case catalog
        case failure
        case suspended
    }

    private let executionScript: [Execution]
    private let shutdownShouldFail: Bool
    private var executeCountWaiters:
        [UUID: (
            count: Int, continuation: CheckedContinuation<Void, Never>
        )] = [:]
    private(set) var executeCount = 0
    private(set) var cancellationCount = 0
    private(set) var shutdownCount = 0

    init(execution: Execution = .catalog, shutdownShouldFail: Bool = false) {
        executionScript = [execution]
        self.shutdownShouldFail = shutdownShouldFail
    }

    init(executions: [Execution], shutdownShouldFail: Bool = false) {
        executionScript = executions
        self.shutdownShouldFail = shutdownShouldFail
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        executeCount += 1
        resumeExecuteCountWaiters()
        let execution = executionScript[min(executeCount - 1, executionScript.count - 1)]
        switch execution {
        case .catalog:
            let body: String
            let status: HTTPResponseStatus
            if request.url.hasSuffix("/api/version") {
                body = #"{"error":"not ollama"}"#
                status = .notFound
            } else {
                body = #"{"data":[{"id":"applied"},{"id":"replacement"}]}"#
                status = .ok
            }
            return HTTPClientResponse(
                status: status,
                headers: ["content-type": "application/json"],
                body: .bytes(ByteBuffer(string: body))
            )
        case .failure:
            throw Error.executeInjected
        case .suspended:
            do {
                try await Task.sleep(for: .seconds(60))
                throw Error.executeInjected
            } catch is CancellationError {
                cancellationCount += 1
                throw CancellationError()
            }
        }
    }

    func shutdown() async throws {
        shutdownCount += 1
        if shutdownShouldFail {
            throw Error.shutdownInjected
        }
    }

    func waitForExecuteCount(
        _ count: Int,
        timeout: Duration = .seconds(5)
    ) async throws {
        guard executeCount < count else {
            return
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.waitForExecuteCountSignal(count)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw WaitError.executeTimedOut(count)
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }

    private func resumeExecuteCountWaiters() {
        let ready = executeCountWaiters.compactMap { id, waiter in
            waiter.count <= executeCount ? id : nil
        }
        for id in ready {
            executeCountWaiters.removeValue(forKey: id)?.continuation.resume()
        }
    }

    private func waitForExecuteCountSignal(_ count: Int) async throws {
        guard executeCount < count else {
            return
        }
        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume()
                } else {
                    executeCountWaiters[waiterID] = (count, continuation)
                }
            }
        } onCancel: {
            Task { await self.cancelExecuteCountWaiter(waiterID) }
        }
        try Task.checkCancellation()
    }

    private func cancelExecuteCountWaiter(_ id: UUID) {
        executeCountWaiters.removeValue(forKey: id)?.continuation.resume()
    }
}

final class ScriptedSecretStore: SecretStore, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case readInjected
        case writeInjected
        case deleteInjected
    }

    private let lock = NSLock()
    private var values: [SecretAccount: String]
    private var readAttempt = 0
    private var writeAttempt = 0
    private var deleteAttempt = 0
    private var failingReadAttempts: Set<Int> = []
    private var failingWriteAttempts: Set<Int> = []
    private var failingDeleteAttempts: Set<Int> = []

    init(values: [SecretAccount: String] = [:]) {
        self.values = values
    }

    func read(account: SecretAccount) throws -> String? {
        try lock.withLock {
            readAttempt += 1
            guard !failingReadAttempts.contains(readAttempt) else { throw Error.readInjected }
            return values[account]
        }
    }

    func write(_ secret: String, account: SecretAccount) throws {
        try lock.withLock {
            writeAttempt += 1
            guard !failingWriteAttempts.contains(writeAttempt) else { throw Error.writeInjected }
            values[account] = secret
        }
    }

    func delete(account: SecretAccount) throws {
        try lock.withLock {
            deleteAttempt += 1
            guard !failingDeleteAttempts.contains(deleteAttempt) else { throw Error.deleteInjected }
            values[account] = nil
        }
    }

    func value(for account: SecretAccount) -> String? {
        lock.withLock { values[account] }
    }

    func failReads(on attempts: Set<Int>) { lock.withLock { failingReadAttempts = attempts } }
    func failWrites(on attempts: Set<Int>) { lock.withLock { failingWriteAttempts = attempts } }
    func failDeletes(on attempts: Set<Int>) { lock.withLock { failingDeleteAttempts = attempts } }

    func failNextRead() { lock.withLock { _ = failingReadAttempts.insert(readAttempt + 1) } }
    func failNextWrite() { lock.withLock { _ = failingWriteAttempts.insert(writeAttempt + 1) } }
    func failNextDelete() { lock.withLock { _ = failingDeleteAttempts.insert(deleteAttempt + 1) } }
}
