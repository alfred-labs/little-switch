import AsyncHTTPClient
import Foundation
import LittleSwitchCore
import LittleSwitchTransport
import NIOCore
import NIOHTTP1

@testable import LittleSwitchUI

actor TestGatewayServer: GatewayServing {
    private(set) var isRunning = false

    func start() async throws {
        isRunning = true
    }

    func stop() async {
        isRunning = false
    }
}

actor TestGatewayTransport: UpstreamTransport {
    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        throw CancellationError()
    }

    func shutdown() async throws {}
}

final class TestTrafficRecorder: TrafficRecording, @unchecked Sendable {
    func record(eventID: UUID, action: TrafficAction) {
        _ = eventID
        _ = action
    }
}

final class CapturingGatewayBuilder: GatewayBuilding, @unchecked Sendable {
    private let lock = NSLock()
    private let expectedRecorder: TestTrafficRecorder
    private let server = TestGatewayServer()
    private var capturedExpectedRecorder = false

    init(
        expectedRecorder: TestTrafficRecorder,
    ) {
        self.expectedRecorder = expectedRecorder
    }

    var receivedExpectedRecorder: Bool {
        lock.withLock { capturedExpectedRecorder }
    }

    func makeGateway(_ context: GatewayBuildContext) -> any GatewayServing {
        lock.withLock {
            capturedExpectedRecorder = context.trafficRecorder as AnyObject === expectedRecorder
        }
        return server
    }
}

actor StaticCatalogTransport: UpstreamTransport {
    private(set) var didShutdown = false
    private var catalogBody: String

    init(catalogBody: String = #"{"data":[{"id":"applied"},{"id":"replacement"}]}"#) {
        self.catalogBody = catalogBody
    }

    func serveCatalog(_ body: String) {
        catalogBody = body
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        // GETs serve the discovery catalog; POSTs are the save-time endpoint
        // probe, and a 403 keeps every verdict `.unknown` so this shared
        // fixture stays probe-neutral — it must not silently seed
        // supportsNative verdicts into coordinators it knows nothing about.
        let status: HTTPResponseStatus = request.method == .POST ? .forbidden : .ok
        return HTTPClientResponse(
            status: status,
            headers: ["content-type": "application/json"],
            body: .bytes(ByteBuffer(string: catalogBody))
        )
    }

    func shutdown() async throws {
        didShutdown = true
    }
}

final class TestClaudeProfileManager: ClaudeProfileManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var active: Bool
    private var restoreCalls = 0

    init(active: Bool = false) {
        self.active = active
    }

    var restoreCount: Int {
        lock.withLock { restoreCalls }
    }

    func activate(autoMode: Bool, tlsEnabled: Bool) throws {
        _ = autoMode
        lock.withLock { active = true }
    }

    func restore() throws {
        lock.withLock {
            restoreCalls += 1
            active = false
        }
    }

    func isActive(autoMode: Bool) throws -> Bool {
        _ = autoMode
        return lock.withLock { active }
    }
}

final class SharedEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func append(_ entry: String) {
        lock.withLock { entries.append(entry) }
    }

    var recorded: [String] {
        lock.withLock { entries }
    }
}

@MainActor
final class TestClaudeController: ClaudeApplicationControlling {
    enum Error: Swift.Error, Equatable {
        case quitInjected
        case openInjected
    }

    private(set) var quitCount = 0
    private(set) var openCount = 0
    private var running: Bool
    private var shouldFailNextQuit = false
    private var shouldFailNextOpen = false

    init(running: Bool = false) {
        self.running = running
    }

    func isRunning() -> Bool { running }

    func quitAndWait() async throws {
        if shouldFailNextQuit {
            shouldFailNextQuit = false
            throw Error.quitInjected
        }
        quitCount += 1
        running = false
    }

    func open() async throws {
        openCount += 1
        if shouldFailNextOpen {
            shouldFailNextOpen = false
            throw Error.openInjected
        }
        running = true
    }

    func failNextQuit() {
        shouldFailNextQuit = true
    }

    func failNextOpen() {
        shouldFailNextOpen = true
    }
}

@MainActor
final class TestCodexController: CodexApplicationControlling {
    enum Error: Swift.Error, Equatable {
        case quitInjected
        case openInjected
    }

    private(set) var quitCount = 0
    private(set) var openCount = 0
    private var running: Bool
    private var shouldFailNextQuit = false
    private var shouldFailNextOpen = false
    var eventLog: SharedEventLog?

    init(running: Bool = false) {
        self.running = running
    }

    func isRunning() -> Bool { running }

    func quitAndWait() async throws {
        if shouldFailNextQuit {
            shouldFailNextQuit = false
            throw Error.quitInjected
        }
        quitCount += 1
        running = false
        eventLog?.append("codex-quit")
    }

    func open() async throws {
        openCount += 1
        if shouldFailNextOpen {
            shouldFailNextOpen = false
            throw Error.openInjected
        }
        running = true
        eventLog?.append("codex-open")
    }

    func failNextQuit() {
        shouldFailNextQuit = true
    }

    func failNextOpen() {
        shouldFailNextOpen = true
    }
}

final class TestClaudeCodeProfileManager: ClaudeCodeProfileManaging, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case activateInjected
        case restoreInjected
        case statusInjected
    }

    private let lock = NSLock()
    private var currentStatus: ClaudeCodeProfileStatus
    private var activationInputs: [ClaudeCodeManagedSettings] = []
    private var restoreCalls = 0
    private var statusInputs: [ClaudeCodeManagedSettings?] = []
    private var shouldFailNextActivation = false
    private var shouldFailNextRestore = false
    private var shouldFailStatus = false
    private var activationAttempt = 0
    private var failingActivationAttempts: Set<Int> = []

    init(status: ClaudeCodeProfileStatus = .inactive) {
        currentStatus = status
    }

    var activations: [ClaudeCodeManagedSettings] {
        lock.withLock { activationInputs }
    }

    var restoreCount: Int {
        lock.withLock { restoreCalls }
    }

    var expectedStatuses: [ClaudeCodeManagedSettings?] {
        lock.withLock { statusInputs }
    }

    func activate(managed: ClaudeCodeManagedSettings) throws {
        try lock.withLock {
            activationAttempt += 1
            let shouldFail =
                shouldFailNextActivation
                || failingActivationAttempts.remove(activationAttempt) != nil
            if shouldFail {
                shouldFailNextActivation = false
                throw Error.activateInjected
            }
            activationInputs.append(managed)
            currentStatus = .active
        }
    }

    func restore() throws {
        try lock.withLock {
            if shouldFailNextRestore {
                shouldFailNextRestore = false
                throw Error.restoreInjected
            }
            restoreCalls += 1
            currentStatus = .inactive
        }
    }

    func status(
        expected: ClaudeCodeManagedSettings?
    ) throws -> ClaudeCodeProfileStatus {
        try lock.withLock {
            statusInputs.append(expected)
            if shouldFailStatus {
                throw Error.statusInjected
            }
            return currentStatus
        }
    }

    func setStatus(_ status: ClaudeCodeProfileStatus) {
        lock.withLock { currentStatus = status }
    }

    func failNextActivation() {
        lock.withLock { shouldFailNextActivation = true }
    }

    func failActivation(onAttempt attempt: Int) {
        lock.withLock { _ = failingActivationAttempts.insert(attempt) }
    }

    func failNextRestore() {
        lock.withLock { shouldFailNextRestore = true }
    }

    func failStatus() {
        lock.withLock { shouldFailStatus = true }
    }
}

final class RecordingConfigurationStore: ConfigurationStoring, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case injected
    }

    private let lock = NSLock()
    private var stored: AppConfiguration
    private var savedValues: [AppConfiguration] = []
    private var shouldFailNextSave = false
    private var savesBeforeFailure: Int?

    init(configuration: AppConfiguration) {
        stored = configuration
    }

    var configuration: AppConfiguration {
        lock.withLock { stored }
    }

    var saves: [AppConfiguration] {
        lock.withLock { savedValues }
    }

    func load() throws -> AppConfiguration {
        lock.withLock { stored }
    }

    func save(_ configuration: AppConfiguration) throws {
        try lock.withLock {
            if shouldFailNextSave || savesBeforeFailure == 0 {
                shouldFailNextSave = false
                savesBeforeFailure = nil
                throw Error.injected
            }
            if let savesBeforeFailure {
                self.savesBeforeFailure = savesBeforeFailure - 1
            }
            stored = configuration
            savedValues.append(configuration)
        }
    }

    func failNextSave() {
        lock.withLock { shouldFailNextSave = true }
    }

    func failSave(afterSuccessfulSaves count: Int) {
        lock.withLock { savesBeforeFailure = count }
    }

    func clearSaves() {
        lock.withLock { savedValues = [] }
    }
}
