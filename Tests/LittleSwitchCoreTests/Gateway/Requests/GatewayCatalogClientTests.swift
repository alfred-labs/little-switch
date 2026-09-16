import Foundation
import HTTPTypes
import HummingbirdTesting
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test(
        "Catalog context choices match the client without duplicating Desktop options",
        arguments: [
            (nil as String?, false),
            ("Claude/1.1.0", false),
            ("curl/8.7.1", false),
            ("claude-code/2.1.273", true),
            ("Claude-Code/2.1.273 (cli)", true),
            ("claude-codeish/2.1.273", false),
            ("proxy/1.0 claude-code/2.1.273", false),
            ("claude-code/", false),
            ("claude-code/ (cli)", false),
        ]
    )
    func catalogClientContextChoices(fixture clientFixture: (String?, Bool)) async throws {
        let (userAgent, explicitChoices) = clientFixture
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)
        let headers: HTTPFields = userAgent.map { [.userAgent: $0] } ?? [:]

        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/v1/models?limit=1000", method: .get, headers: headers)
            #expect(response.status == .ok)
            #expect(response.headers[.vary] == "User-Agent")
            let catalog = try JSONDecoder().decode(ClaudeCatalogResponse.self, from: data(response.body))
            #expect(
                catalog.data.map(\.id)
                    == (explicitChoices ? ["claude-opus-5", "claude-opus-5[1m]"] : ["claude-opus-5"]))
            #expect(catalog.data.first?.supports1M == true)
            if explicitChoices {
                #expect(catalog.data.last?.displayName == "Opus ↦ [1m]")
                #expect(catalog.data.last?.maxInputTokens == 1_000_000)
                #expect(catalog.data.last?.supports1M == false)
            } else {
                // Desktop generates its own extended choice from supports_1m.
                let desktopIDs = catalog.data.flatMap { model in
                    model.supports1M ? [model.id, "\(model.id)[1m]"] : [model.id]
                }
                #expect(desktopIDs == ["claude-opus-5", "claude-opus-5[1m]"])
                #expect(Set(desktopIDs).count == desktopIDs.count)
            }
            #expect(await transport.requests.isEmpty)
        }
    }
}
