import Foundation
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Responses search options")
struct OpenAIResponsesWebSearchOptionsTests {
    @Test("The private search turn disables parallel tool calls")
    func privateSearchIsSequential() throws {
        let request = Data(
            #"{"model":"slug","input":"x","parallel_tool_calls":true,"tools":[{"type":"web_search"},{"type":"function","name":"weather","parameters":{"type":"object"}}]}"#
                .utf8
        )

        let candidate = try OpenAIResponsesWebSearch.prepare(
            body: request,
            targetModel: "target",
            configuration: .firecrawlCloud
        )
        let prepared = try #require(candidate)
        let upstream = try #require(
            JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any]
        )

        #expect(upstream["parallel_tool_calls"] as? Bool == false)
    }

    @Test("Malformed direct Firecrawl option mappings fail during preparation")
    func malformedOptions() throws {
        for tool in [
            #"{"type":"web_search","filters":[]}"#,
            #"{"type":"web_search","filters":{"allowed_domains":[""]}}"#,
            #"{"type":"web_search","user_location":{"type":"precise","country":"FR"}}"#,
            #"{"type":"web_search","user_location":{"type":"approximate","city":7}}"#,
        ] {
            let request = #"{"model":"slug","input":"x","tools":[\#(tool)]}"#
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                try OpenAIResponsesWebSearch.prepare(
                    body: Data(request.utf8),
                    targetModel: "target",
                    configuration: .firecrawlCloud
                )
            }
        }
    }

    @Test("A country-only search location does not invent a city or region")
    func countryOnlyLocation() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "model": "slug",
            "input": "Current Swift news",
            "tools": [
                [
                    "type": "web_search",
                    "user_location": ["type": "approximate", "country": " FR "],
                ]
            ],
        ])
        let candidate = try OpenAIResponsesWebSearch.prepare(
            body: body,
            targetModel: "provider",
            configuration: .firecrawlCloud
        )
        let prepared = try #require(candidate)
        #expect(prepared.searchOptions == WebSearchFilterOptions(country: "FR"))
    }

    @Test("A tool name without a native type does not establish search ownership")
    func untypedToolDoesNotOwnSearch() {
        #expect(!OpenAIResponsesWebSearch.isBuiltInSearchTool(["name": "web_search"]))
        #expect(!OpenAIResponsesWebSearch.isBuiltInSearchTool([:]))
    }
}
