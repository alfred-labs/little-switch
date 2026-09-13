import Foundation
import LittleSwitchWire

package enum AnthropicCountTokensRequest {
    package enum Error: Swift.Error, Equatable {
        case invalidRequest
        case invalidResponse
    }

    package static func project(_ upstreamBody: Data) throws -> Data {
        let request: AnthropicCountTokensProjection
        do {
            let document = try WireCodec.decode(AnthropicCountTokensProjection.self, from: upstreamBody)
            let root = try WireObject(document.value.wireJSON()).additionalFields(excluding: [])
            let portable = try PortableToolHistory.anthropic(root)
            request = try AnthropicCountTokensProjection(wireJSON: anthropicJSON(portable))
        } catch let error as PortableToolHistory.Error {
            throw error
        } catch let error as PortableWebSearchHistory.Error {
            throw error
        } catch {
            throw Error.invalidRequest
        }
        var projected = request
        projected.additionalFields = [:]
        return try WireCodec.encode(projected)
    }

    package static func parseCount(_ responseBody: Data) throws -> Int {
        guard let response = try? WireCodec.decode(AnthropicInputTokenCount.self, from: responseBody).value,
            let count = try? response.inputTokens.integerValue(), count > 0
        else {
            throw Error.invalidResponse
        }
        return count
    }
}
