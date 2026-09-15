import AsyncHTTPClient
import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Custom capability witness classification boundaries")
struct CustomToolCapabilityResponseEdgeTests {
    @Test("Malformed JSON cannot be evidence of a completed native witness", arguments: ["", "not-json", "[]"])
    func malformedResponse(body: String) {
        #expect(
            CustomToolCapabilityResponse.classify(
                body: Data(body.utf8), status: 200, wire: .responses, marker: "marker", envelope: false)
                == .inconclusive)
    }

    @Test("A valid witness is accepted at the response byte limit but not one byte beyond it")
    func boundedResponse() {
        var body = Data(Self.responses.utf8)
        body.append(Data(repeating: 0x20, count: 65_536 - body.count))
        #expect(
            CustomToolCapabilityResponse.classify(
                body: body, status: 200, wire: .responses, marker: "marker", envelope: false) == .matched)
        body.append(0x20)
        #expect(
            CustomToolCapabilityResponse.classify(
                body: body, status: 200, wire: .responses, marker: "marker", envelope: false) == .inconclusive)
    }

    @Test("Explicit null metadata does not invalidate an otherwise exact witness", arguments: nullableWitnesses)
    func explicitNulls(fixture: CustomCapabilityWitnessFixture) {
        #expect(
            CustomToolCapabilityResponse.classify(
                body: Data(fixture.body.utf8),
                status: 200,
                wire: fixture.wire,
                marker: "marker",
                envelope: fixture.envelope) == .matched)
    }

    @Test(
        "Errors, legacy calls and unexpected namespaces cannot masquerade as a successful witness", arguments: conflicts
    )
    func conflictingMetadata(fixture: CustomCapabilityWitnessFixture) {
        #expect(
            CustomToolCapabilityResponse.classify(
                body: Data(fixture.body.utf8),
                status: 200,
                wire: fixture.wire,
                marker: "marker",
                envelope: fixture.envelope) == .inconclusive)
    }

    @Test(
        "A precise optional-control rejection without a code retries only that control", arguments: optionalRejections)
    func optionalRejectionWithoutCode(fixture: CustomCapabilityOptionalRejection) async throws {
        let transport = CustomCapabilityProbeTransport([.http(fixture.status, fixture.body), .echo])
        let template =
            fixture.wire == .responses
            ? customCapabilityTemplate()
            : HTTPClientRequest(url: "https://api.z.ai/api/coding/paas/v4/chat/completions")
        let result = try await CustomToolCapabilityProber(transport: transport).probe(
            template: template, modelID: "model", wire: fixture.wire)
        #expect(result == .native)
        let requests = await transport.requests
        try #require(requests.count == 2)
        var original = try #require(JSONValue.parse(requests[0].body).object)
        let removed = original.removeValue(forKey: fixture.control)
        #expect(removed != nil)
        #expect(try JSONValue.object(original) == JSONValue.parse(requests[1].body))
    }

    @Test("An invalid custom declaration value permits the strict function witness", arguments: [400, 422])
    func invalidCustomValue(status: Int) async throws {
        let body = #"{"error":{"param":"tools[0].type","message":"Invalid value: 'custom'."}}"#
        let transport = CustomCapabilityProbeTransport([.http(status, body), .echo])
        #expect(
            try await CustomToolCapabilityProber(transport: transport).probe(
                template: customCapabilityTemplate(), modelID: "model", wire: .responses) == .functionEnvelope)
        #expect(await transport.requests.count == 2)
    }

    private static let responses =
        #"{"status":"completed","error":null,"output":[{"type":"custom_tool_call","status":"completed","call_id":"probe_call","#
        + #""name":"littleswitch_custom_probe","namespace":null,"input":"marker"}]}"#
    private static let chat =
        #"{"error":null,"choices":[{"finish_reason":"tool_calls","message":{"role":"assistant","content":null,"function_call":null,"#
        + #""tool_calls":[{"id":"probe_call","type":"custom","custom":{"name":"littleswitch_custom_probe","namespace":null,"#
        + #""input":"marker"}}]}}]}"#

    private static let nullableWitnesses: [CustomCapabilityWitnessFixture] = [
        .init(wire: .responses, body: responses),
        .init(wire: .chatCompletions, body: chat),
        .init(
            wire: .responses,
            body:
                #"{"status":"completed","error":null,"output":[{"type":"function_call","status":"completed","call_id":"probe_call","#
                + #""name":"littleswitch_custom_probe","namespace":null,"arguments":"{\"input\":\"marker\"}"}]}"#,
            envelope: true),
        .init(
            wire: .chatCompletions,
            body:
                #"{"error":null,"choices":[{"finish_reason":"tool_calls","message":{"role":"assistant","content":null,"function_call":null,"#
                + #""tool_calls":[{"id":"probe_call","type":"function","function":{"name":"littleswitch_custom_probe","namespace":null,"#
                + #""arguments":"{\"input\":\"marker\"}"}}]}}]}"#,
            envelope: true),
    ]

    private static let conflicts: [CustomCapabilityWitnessFixture] = [
        .init(
            wire: .responses,
            body: responses.replacingOccurrences(
                of: #""error":null"#, with: #""error":{"message":"generation failed"}"#)),
        .init(
            wire: .chatCompletions,
            body: chat.replacingOccurrences(
                of: #""error":null"#, with: #""error":{"message":"generation failed"}"#)),
        .init(
            wire: .chatCompletions,
            body: chat.replacingOccurrences(
                of: #""function_call":null"#,
                with: #""function_call":{"name":"legacy","arguments":"{}"}"#)),
        .init(
            wire: .responses,
            body: responses.replacingOccurrences(of: #""namespace":null"#, with: #""namespace":"other""#)),
        .init(
            wire: .chatCompletions,
            body: chat.replacingOccurrences(of: #""namespace":null"#, with: #""namespace":"other""#)),
    ]

    private static let optionalRejections: [CustomCapabilityOptionalRejection] = [
        .init(
            wire: .responses,
            control: "reasoning",
            status: 400,
            body: #"{"error":{"message":"Unsupported parameter: 'reasoning.effort'."}}"#),
        .init(
            wire: .responses,
            control: "reasoning",
            status: 422,
            body: #"{"error":{"message":"Unrecognized request argument supplied: reasoning"}}"#),
        .init(
            wire: .responses,
            control: "reasoning",
            status: 400,
            body: #"{"error":{"param":"reasoning.effort","message":"This value is not supported for this model."}}"#),
        .init(
            wire: .chatCompletions,
            control: "thinking",
            status: 422,
            body: #"{"error":{"message":"Unknown parameter: \"thinking.type\"."}}"#),
    ]
}

struct CustomCapabilityWitnessFixture: Sendable {
    let wire: ProviderToolContract.Wire
    let body: String
    var envelope = false
}

struct CustomCapabilityOptionalRejection: Sendable {
    let wire: ProviderToolContract.Wire
    let control: String
    let status: Int
    let body: String
}
