import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

@testable import LittleSwitchCore

@Suite("Gateway monitoring admission")
struct GatewayMonitoringAdmissionTests {
    @Test("Admission retains its exact failure category before producing the common HTTP error")
    func failureCategories() async throws {
        for (failure, kind, metric) in [
            (
                GatewayAdmissionError.overloaded, MonitoringErrorKind.overloaded,
                MonitoringMetricName.admissionRejections
            ),
            (.timedOut, .timeout, .admissionTimeouts), (.invalidated, .invalidated, .admissionRejections),
            (.notAcceptingRequests, .shutdown, .admissionRejections),
        ] {
            let fixture = try GatewayTests().makeFixture()
            let store = MonitoringStore()
            let app = Application(
                responder: GatewayResponder(
                    state: fixture.state,
                    transport: RecordingGatewayTransport(responses: []),
                    secretStore: fixture.secrets,
                    requiredAuthorityPort: nil,
                    monitoring: GatewayMonitoring(store: store),
                    dependencies: .init(admitter: MonitoringRejectedAdmission(failure: failure))))
            try await app.test(.router) { client in
                let response = try await client.execute(
                    uri: "/v1/messages",
                    method: .post,
                    headers: [.contentType: "application/json"],
                    body: .init(string: #"{"model":"claude-opus-5","messages":[]}"#))
                #expect(response.status == .serviceUnavailable)
            }
            let snapshot = await store.snapshot()
            #expect(snapshot.family(metric)?.points.map(\.value) == [.counter(1)])
            #expect(snapshot.family(.requests)?.points.map(\.value) == [.counter(1)])
            #expect(try await store.logs().entries.first?.attributes.errorKind == kind)
        }
    }
}

private struct MonitoringRejectedAdmission: GatewayAdmitting {
    let failure: GatewayAdmissionError

    func admit(state: GatewayState, request: GatewayRequestAdmission) async throws {
        throw failure
    }
}
