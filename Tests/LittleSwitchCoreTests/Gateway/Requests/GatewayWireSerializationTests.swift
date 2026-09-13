import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Gateway wire serialization")
struct GatewayWireSerializationTests {
    @Test("Routing an Anthropic request preserves exact tool schemas and opaque values")
    func anthropicModelRewritePreservesOpaqueValues() throws {
        let source = Data(
            #"""
            {"model":"public","messages":[],"max_tokens":10,"tools":[
              {"name":"read","input_schema":{"type":"object","vendor":1e400}}],
             "vendor":{"large":18446744073709551615,"tiny":1e-999}}
            """#.utf8)
        let expected = Data(
            #"""
            {"model":"physical","messages":[],"max_tokens":10,"tools":[
              {"name":"read","input_schema":{"type":"object","vendor":1e400}}],
             "vendor":{"large":18446744073709551615,"tiny":1e-999}}
            """#.utf8)
        let rewritten = try LiveGatewaySerializer().rewriteMessage(source, modelID: "physical")
        #expect(try JSONValue.parse(rewritten) == JSONValue.parse(expected))
    }

    @Test("Routing a Responses request preserves opaque JSON and exact numbers")
    func responsesModelRewritePreservesOpaqueValues() throws {
        let source = Data(
            #"""
            {"model":"public","stream":true,"input":"Δ","vendor":{
                "large":18446744073709551615,"tiny":1e-999,
                "decimal":0.1234567890123456789012345678901234567890123456789,"nullable":null}}
            """#
            .utf8
        )
        let expected = Data(
            #"""
            {"model":"physical","stream":true,"input":"Δ","vendor":{
                "large":18446744073709551615,"tiny":1e-999,
                "decimal":0.1234567890123456789012345678901234567890123456789,"nullable":null}}
            """#
            .utf8
        )
        let rewritten = try LiveGatewaySerializer().rewriteResponses(source, modelID: "physical")
        #expect(try JSONValue.parse(rewritten) == JSONValue.parse(expected))
    }

    @Test("The selected route replaces an absent or malformed incoming model")
    func selectedRouteOwnsModelReplacement() throws {
        let serializer = LiveGatewaySerializer()
        for body in [#"{"input":"hello"}"#, #"{"model":null,"input":"hello"}"#, #"{"model":false,"input":"hello"}"#] {
            let rewritten = try serializer.rewriteResponses(Data(body.utf8), modelID: "physical")
            #expect(try JSONValue.parse(rewritten) == JSONValue.parse(#"{"input":"hello","model":"physical"}"#))
        }
    }
}
