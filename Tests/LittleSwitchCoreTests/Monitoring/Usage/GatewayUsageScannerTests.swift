import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Gateway usage scanner")
struct GatewayUsageScannerTests {
    @Test("An empty body reports no usage")
    func emptyBody() {
        #expect(GatewayUsageScanner.totals(in: Data()) == nil)
    }

    @Test("Anthropic buffered usage keeps cache counters beside input")
    func anthropicBufferedUsage() {
        let body = Data(
            """
            {"usage":{"input_tokens":10,"output_tokens":5,\
            "cache_read_input_tokens":3,"cache_creation_input_tokens":2}}
            """.utf8
        )

        #expect(
            GatewayUsageScanner.totals(in: body)
                == GatewayUsageTotals(
                    inputTokens: 10,
                    outputTokens: 5,
                    cacheReadTokens: 3,
                    cacheWriteTokens: 2
                )
        )
    }

    @Test("OpenAI prompt tokens shed the cached share so fields stay disjoint")
    func openAIBufferedUsage() {
        let body = Data(
            """
            {"usage":{"prompt_tokens":100,"completion_tokens":20,\
            "prompt_tokens_details":{"cached_tokens":40}}}
            """.utf8
        )

        let totals = GatewayUsageScanner.totals(in: body)

        #expect(totals == GatewayUsageTotals(inputTokens: 60, outputTokens: 20, cacheReadTokens: 40))
        #expect(totals?.total == 120)
    }

    @Test("Responses usage sheds the cached and written share from its input count")
    func responsesEnvelopeUsage() {
        let body = Data(
            """
            {"response":{"usage":{"input_tokens":30,"output_tokens":8,\
            "input_tokens_details":{"cached_tokens":12,"cache_write_tokens":3}}}}
            """.utf8
        )

        let totals = GatewayUsageScanner.totals(in: body)

        #expect(
            totals
                == GatewayUsageTotals(
                    inputTokens: 15,
                    outputTokens: 8,
                    cacheReadTokens: 12,
                    cacheWriteTokens: 3
                )
        )
        #expect(totals?.total == 38)
    }

    @Test("A message envelope reports its own usage")
    func messageEnvelopeUsage() {
        let body = Data(#"{"message":{"usage":{"input_tokens":7,"output_tokens":1}}}"#.utf8)

        #expect(
            GatewayUsageScanner.totals(in: body)
                == GatewayUsageTotals(inputTokens: 7, outputTokens: 1)
        )
    }

    @Test("Output-only usage survives without an input count")
    func outputOnlyUsage() {
        let body = Data(#"{"usage":{"output_tokens":4}}"#.utf8)

        #expect(GatewayUsageScanner.totals(in: body) == GatewayUsageTotals(outputTokens: 4))
    }

    @Test("An empty usage object reports nothing")
    func emptyUsageObject() {
        #expect(GatewayUsageScanner.totals(in: Data(#"{"usage":{}}"#.utf8)) == nil)
    }

    @Test("Unusable counts are ignored")
    func unusableCounts() {
        let negative = Data(#"{"usage":{"input_tokens":-4,"output_tokens":2}}"#.utf8)
        let text = Data(#"{"usage":{"input_tokens":"many","output_tokens":2}}"#.utf8)
        let nested = Data(#"{"usage":{"output_tokens":2,"input_tokens_details":6}}"#.utf8)

        #expect(GatewayUsageScanner.totals(in: negative) == GatewayUsageTotals(outputTokens: 2))
        #expect(GatewayUsageScanner.totals(in: text) == GatewayUsageTotals(outputTokens: 2))
        #expect(GatewayUsageScanner.totals(in: nested) == GatewayUsageTotals(outputTokens: 2))
    }

    @Test("A document without usage reports nothing")
    func documentWithoutUsage() {
        #expect(GatewayUsageScanner.totals(in: Data(#"{"id":"msg_1"}"#.utf8)) == nil)
        #expect(GatewayUsageScanner.totals(in: Data(#"{"response":{"id":"resp_1"}}"#.utf8)) == nil)
        #expect(GatewayUsageScanner.totals(in: Data("[1,2,3]".utf8)) == nil)
    }

    @Test("Streamed usage merges the opening and closing frames")
    func streamedUsage() {
        let body = Data(
            """
            event: message_start
            data: {"type":"message_start","message":{"usage":{"input_tokens":42,"output_tokens":1}}}

            event: ping
            data: {"type":"ping"}

            data: not json

            data:

            : comment

            event: message_delta
            data: {"type":"message_delta","usage":{"output_tokens":137}}

            data: [DONE]

            """.utf8
        )

        #expect(
            GatewayUsageScanner.totals(in: body)
                == GatewayUsageTotals(inputTokens: 42, outputTokens: 137)
        )
    }

    @Test("Carriage returns and spacing around the payload are tolerated")
    func streamedUsageWithCarriageReturns() {
        let body = Data("data:  {\"usage\":{\"output_tokens\":9}} \r\n".utf8)

        #expect(GatewayUsageScanner.totals(in: body) == GatewayUsageTotals(outputTokens: 9))
    }

    @Test("A terminal frame carrying the whole answer on one line still reports usage")
    func oversizedTerminalFrame() {
        var body = Data(
            """
            data: {"type":"message_start","message":{"usage":{"input_tokens":11}}}

            """.utf8
        )
        let filler = Data("data: {\"type\":\"content_block_delta\"}\n\n".utf8)
        while body.count < 256 * 1_024 {
            body.append(filler)
        }
        // One line the size of the transcript, with the usage object at its end —
        // the shape a Responses `response.completed` frame actually takes.
        let transcript = String(repeating: "a", count: 512 * 1_024)
        body.append(
            Data(
                """
                data: {"type":"response.completed","response":{"output":"\(transcript)",\
                "usage":{"input_tokens":40801,"output_tokens":922,\
                "input_tokens_details":{"cached_tokens":40576,"cache_write_tokens":0}}}}

                """.utf8
            )
        )

        #expect(
            GatewayUsageScanner.totals(in: body)
                == GatewayUsageTotals(
                    inputTokens: 225,
                    outputTokens: 922,
                    cacheReadTokens: 40_576
                )
        )
    }

    @Test("An unterminated usage object reports nothing")
    func unterminatedUsageObject() {
        #expect(GatewayUsageScanner.totals(in: Data(#"data: {"usage":{"input_tokens":4"#.utf8)) == nil)
        #expect(GatewayUsageScanner.totals(in: Data(#"data: {"usage":42}"#.utf8)) == nil)
        #expect(GatewayUsageScanner.totals(in: Data(#"data: {"usage":"#.utf8)) == nil)
    }

    @Test("A brace inside a string does not end the usage object early")
    func bracesInsideStrings() {
        let body = Data(
            #"""
            data: {"usage":{"note":"} \" {","input_tokens":5,"output_tokens":2}}
            """#.utf8
        )

        #expect(
            GatewayUsageScanner.totals(in: body)
                == GatewayUsageTotals(inputTokens: 5, outputTokens: 2)
        )
    }

    @Test("ToolSearch calls are counted by marker in buffered and stream bodies")
    func toolSearchCalls() {
        let buffered = Data(
            #"{"content":[{"type":"tool_use","id":"toolu_1","name":"ToolSearch","input":{}}]}"#.utf8
        )
        #expect(GatewayUsageScanner.toolSearchCalls(in: buffered) == 1)

        let stream = Data(
            """
            event: content_block_start
            data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_a","name":"ToolSearch","input":{}}}

            event: content_block_start
            data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_b","name":"ToolSearch","input":{}}}

            event: content_block_start
            data: {"type":"content_block_start","index":3,"content_block":{"type":"tool_use","id":"toolu_c","name":"Bash","input":{}}}
            """.utf8
        )
        #expect(GatewayUsageScanner.toolSearchCalls(in: stream) == 2)

        let none = Data(#"{"content":[{"type":"text","text":"outils chargés via ToolSearch déjà connu"}]}"#.utf8)
        #expect(GatewayUsageScanner.toolSearchCalls(in: none) == 0)
        #expect(GatewayUsageScanner.toolSearchCalls(in: Data()) == 0)
    }

}
