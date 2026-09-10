import Foundation
import Testing

@testable import RepositoryTooling

@Suite("End-of-conversation tool definition metrics")
struct SessionToolDefinitionsTests {
    @Test("Canonical prefixes preserve escaped Unicode, scalar kinds and Python diagnostic spacing")
    func canonicalPrefix() throws {
        let source = #"{"a":[null,true,1,1.0,0.000001,1e-7],"b":"é😀 \" \\ /"}"#
        #expect(
            try DiagnosticMessagePrefix.encode(DiagnosticJSONReader.read(Data(source.utf8)))
                == #"{"a": [null, true, 1, 1.0, 1e-06, 1e-07], "b": "\u00e9\ud83d\ude00 \" \\ /"}"#)
    }

    @Test("The last request, peak, count and ToolSearch flag belong to each conversation")
    func lastRequest() throws {
        var analyzer = SessionToolDefinitions()
        for names in [["ToolSearch", "mcp__a", "mcp__b"], ["mcp__a", "ToolSearch"]] {
            analyzer.ingest(try request(names: names))
        }
        analyzer.ingest(try request(model: "second", names: ["read", "mcp__c"]))
        #expect(
            analyzer.summaries == [
                .init(model: "fixture", requests: 2, maximumDefinitions: 2, lastDefinitions: 1, usesToolSearch: true),
                .init(model: "second", requests: 1, maximumDefinitions: 1, lastDefinitions: 1, usesToolSearch: false),
            ])
    }

    @Test("Messages and builtin tool sets separate groups; dictionary key and tool order do not")
    func grouping() throws {
        var analyzer = SessionToolDefinitions()
        analyzer.ingest(try request(names: ["read", "write"], message: ["role": "user", "content": "hello"]))
        analyzer.ingest(
            try request(names: ["write", "read", "mcp__a"], message: ["content": "hello", "role": "user"]))
        analyzer.ingest(try request(names: ["read"]))
        analyzer.ingest(try request(names: ["read", "write"], message: ["role": "user", "content": "different"]))
        #expect(analyzer.summaries.map(\.requests) == [2, 1, 1])
        #expect(analyzer.summaries.map(\.lastDefinitions) == [1, 0, 0])
    }

    @Test(
        "The documented 400-character ASCII-escaped first-message prefix remains a heuristic",
        arguments: ["é", "\u{7F}"])
    func prefix(character: String) throws {
        var analyzer = SessionToolDefinitions()
        let prefix = String(repeating: character, count: 80)
        for suffix in ["first", "second"] {
            analyzer.ingest(try request(names: [], message: ["content": prefix + suffix, "role": "user"]))
        }
        #expect(analyzer.summaries.map(\.requests) == [2])
    }

    @Test("Large JSON integers cannot collapse into the same double-valued conversation key")
    func largeIntegerIdentity() throws {
        var analyzer = SessionToolDefinitions()
        for number in ["18446744073709551616", "18446744073709551617"] {
            analyzer.ingest(try envelope(Data("{\"messages\":[{\"content\":\(number)}]}".utf8)))
        }
        #expect(analyzer.summaries.map(\.requests) == [1, 1])
    }

    @Test("Original numeric kinds and arbitrary-size integer values survive the complete request envelope")
    func originalNumbers() throws {
        var analyzer = SessionToolDefinitions()
        for number in [
            "18446744073709551617", "18446744073709551617.0",
            "1.00000000000000000001", "1.00000000000000000002",
            String(repeating: "9", count: 201),
        ] {
            analyzer.ingest(try envelope(Data("{\"messages\":[{\"content\":\(number)}]}".utf8)))
        }
        #expect(analyzer.summaries.map(\.requests) == [2, 1, 1, 1])
    }

    @Test("Absent or malformed tool lists contribute zero definitions", arguments: [nil, "invalid"] as [String?])
    func absentTools(value: String?) throws {
        var analyzer = SessionToolDefinitions()
        var body: [String: Any] = ["messages": [["content": "hello"]]]
        if let value { body["tools"] = value }
        analyzer.ingest(try envelope(JSONSerialization.data(withJSONObject: body)))
        #expect(
            analyzer.summaries == [
                .init(model: "?", requests: 1, maximumDefinitions: 0, lastDefinitions: 0, usesToolSearch: false)
            ])
    }

    @Test("Malformed lines and missing request envelopes cannot create sessions")
    func malformed() throws {
        var analyzer = SessionToolDefinitions()
        for text in ["{", "null", "[]", "{}", #"{"action":"bad"}"#, #"{"action":{"claudeRequestBody":{"_0":"???"}}}"#] {
            analyzer.ingest(Data(text.utf8))
        }
        for body in ["{", "[]", "{}", #"{"messages":[]}"#, #"{"messages":"invalid"}"#] {
            analyzer.ingest(try envelope(Data(body.utf8)))
        }
        #expect(analyzer.summaries.isEmpty)
        #expect(analyzer.report() == "no sessions found\n")
    }

    @Test("Only aggregate metrics appear in the complete deterministic table")
    func report() throws {
        var analyzer = SessionToolDefinitions()
        analyzer.ingest(try request(names: ["ToolSearch", "mcp__a"], message: ["content": "PRIVATE CONTENT"]))
        let header = "model                     reqs   TS last_defs max_defs  ratio\n"
        #expect(
            analyzer.report(mounted: 20) == header + "fixture                      1  oui         1        1  1/20\n")
        #expect(analyzer.report() == header + "fixture                      1  oui         1        1  -\n")
        #expect(analyzer.report(mounted: 0) == analyzer.report())
    }

    @Test("Unknown models, unnamed tools and non-dictionary tool entries retain bounded metrics")
    func irregularTools() throws {
        var analyzer = SessionToolDefinitions()
        let body: [String: Any] = [
            "messages": [["role": "user", "content": "hello"]], "tools": [true, [:], ["name": "mcp__x"]],
        ]
        analyzer.ingest(try envelope(JSONSerialization.data(withJSONObject: body)))
        #expect(
            analyzer.summaries == [
                .init(model: "?", requests: 1, maximumDefinitions: 1, lastDefinitions: 1, usesToolSearch: false)
            ])
    }

    private func request(
        model: String = "fixture", names: [String], message: [String: Any] = ["content": "hello", "role": "user"]
    ) throws -> Data {
        try envelope(
            JSONSerialization.data(withJSONObject: [
                "model": model, "messages": [message], "tools": names.map { ["name": $0] },
            ]))
    }

    private func envelope(_ body: Data) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["action": ["claudeRequestBody": ["_0": body.base64EncodedString()]]]
        )
    }
}
