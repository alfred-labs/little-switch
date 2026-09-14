import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring gateway lifecycle")
struct MonitoringGatewayLifecycleTests {
    @Test("A ready run emits one start and stop; startup failure emits neither")
    func lifecycle() async throws {
        for ready in [true, false] {
            let fixture = try GatewayTests().makeFixture()
            let store = MonitoringStore()
            let server = GatewayServer(
                state: fixture.state,
                transport: RecordingGatewayTransport(responses: []),
                secretStore: fixture.secrets,
                runnerFactory: MonitoringLifecycleRunnerFactory(ready: ready),
                monitoring: GatewayMonitoring(store: store)
            )
            do {
                if ready {
                    try await server.start()
                } else {
                    await #expect(throws: GatewayTestError.privateFailure) { try await server.start() }
                }
                await server.stop()
                await server.stop()
                let entries = try await store.logs().entries
                #expect(entries.map(\.eventName) == (ready ? ["gateway.started", "gateway.stopped"] : []))
                #expect(await store.snapshot().family(.requests) == nil)
            } catch {
                await server.stop()
                throw error
            }
        }
    }

    @Test("Stop waits for the started observation before submitting the stopped observation")
    func orderedHandoff() async throws {
        let fixture = try GatewayTests().makeFixture()
        let store = MonitoringStore()
        let probe = MonitoringLifecycleLogProbe()
        let monitoring = GatewayMonitoring(store: store) {
            .init()
        } recordLog: {
            await probe.record($0)
        }
        let server = GatewayServer(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            runnerFactory: MonitoringLifecycleRunnerFactory(ready: true),
            monitoring: monitoring
        )
        let start = Task { try await server.start() }
        do {
            try await probe.started.wait(timeout: .seconds(5), description: "the started observation")
            let stop = Task { await server.stop() }
            await probe.release.open()
            try await start.value
            await stop.value
            #expect(await probe.names == ["gateway.started", "gateway.stopped"])
        } catch {
            await probe.release.open()
            start.cancel()
            _ = try? await start.value
            await server.stop()
            throw error
        }
    }
}

private struct MonitoringLifecycleRunnerFactory: GatewayServerRunnerFactory, GatewayServerRunning {
    let ready: Bool
    private let release = AsyncTestGate()

    func makeRunner(configuration: GatewayServerConfiguration) -> any GatewayServerRunning { self }

    func run(onReady: @escaping @Sendable () -> Void) async throws {
        guard ready else { throw GatewayTestError.privateFailure }
        onReady()
        try await release.wait()
    }
}

private actor MonitoringLifecycleLogProbe {
    nonisolated let started = AsyncTestGate()
    nonisolated let release = AsyncTestGate()
    private(set) var names: [String] = []

    func record(_ entry: MonitoringLogEntry) async {
        if entry.eventName == "gateway.started" {
            await started.open()
            try? await release.wait()
        }
        names.append(entry.eventName)
    }
}
