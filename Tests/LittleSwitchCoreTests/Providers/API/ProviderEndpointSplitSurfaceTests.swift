import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

extension ProviderNetworkingTests {
    @Test("A split-surface provider mounts chat at its root and Claude on the Anthropic URL")
    func splitSurfaceEndpoints() throws {
        let provider = Provider(
            name: "z.ai",
            baseURL: "https://api.z.ai/api/coding/paas/v4",
            authMode: .bearer,
            anthropicBaseURL: "https://api.z.ai/api/anthropic"
        )
        #expect(
            try ProviderEndpoint.forwarding(.chatCompletions, for: provider).absoluteString
                == "https://api.z.ai/api/coding/paas/v4/chat/completions"
        )
        #expect(
            try ProviderEndpoint.forwarding(.responses, for: provider).absoluteString
                == "https://api.z.ai/api/coding/paas/v4/v1/responses"
        )
        #expect(
            try ProviderEndpoint.forwarding(.messages, for: provider).absoluteString
                == "https://api.z.ai/api/anthropic/v1/messages"
        )
    }

    @Test("Ordinary providers keep every route under the base URL")
    func ordinaryEndpoints() throws {
        let provider = Provider(
            name: "Relay",
            baseURL: "https://relay.example/api",
            authMode: .bearer
        )
        #expect(
            try ProviderEndpoint.forwarding(.chatCompletions, for: provider).absoluteString
                == "https://relay.example/api/v1/chat/completions"
        )
        #expect(
            try ProviderEndpoint.forwarding(.messages, for: provider).absoluteString
                == "https://relay.example/api/v1/messages"
        )
    }
}
