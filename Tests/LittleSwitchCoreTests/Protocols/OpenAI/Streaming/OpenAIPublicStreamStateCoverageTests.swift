import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI public stream state coverage")
struct OpenAIPublicStreamStateCoverageTests {
    @Test("Encoding state rejects invalid references and overflow")
    func encodingStateEdges() throws {
        var session = ResponsesPublicStreamSession(webSearch: try preparedWebSearchRequest())
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try session.publicContentReference(
                outputIndex: 0,
                contentIndex: 0,
                itemID: "msg",
                requiredType: "output_text"
            )
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try session.publicFunctionReference(
                outputIndex: 0,
                itemID: "fc",
                callID: "call",
                name: "read"
            )
        }

        session.nextOutputIndex = Int.max
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try session.allocateOutputIndex()
        }
        session.nextSequenceNumber = Int.max
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try session.frame("event", payload: [:])
        }

        session.nextOutputIndex = 1
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try session.completedOutputItems(requireComplete: true)
        }
        session.nextOutputIndex = 0
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try session.finalResponse(
                sourceJSON: responseData([:]),
                terminal: .completed,
                usage: .init(inputTokens: 0, outputTokens: 0)
            )
        }

        let chatPrepared = try OpenAIResponsesChatCompletions.prepare(
            body: responseData(["model": "route", "input": "hello"]),
            targetModel: "provider"
        )
        var chatSession = ResponsesPublicStreamSession(chatCompletions: chatPrepared)
        chatSession.firstResponseJSON = try responseData([
            "id": "resp", "object": "response", "created_at": 1,
        ])
        chatSession.publicResponseID = "resp"
        chatSession.publicCreatedAt = 1
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try chatSession.finalResponse(
                sourceJSON: responseData(["id": "source", "object": "chat.completion"]),
                terminal: .completed,
                usage: .init(inputTokens: 0, outputTokens: 0)
            )
        }
    }

    @Test("Lifecycle rejects invalid start, search, finish, and failure states")
    func lifecycleEdges() throws {
        let prepared = try preparedWebSearchRequest()

        var repeatedStart = ResponsesPublicStreamSession(webSearch: prepared)
        repeatedStart.started = true
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try repeatedStart.start(responseJSON: responseData([:]))
        }

        var missingOutput = ResponsesPublicStreamSession(webSearch: prepared)
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try missingOutput.start(
                responseJSON: responseData([
                    "id": "resp", "object": "response", "created_at": 1,
                ]))
        }

        var missingCreatedAt = ResponsesPublicStreamSession(webSearch: prepared)
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try missingCreatedAt.start(
                responseJSON: responseData([
                    "id": "resp", "object": "response", "output": [],
                ]))
        }

        var searchBeforeStart = ResponsesPublicStreamSession(webSearch: prepared)
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try searchBeforeStart.beginSearch(id: "ws", query: "q")
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try searchBeforeStart.finishSearch(id: "ws", query: "q")
        }

        var finishBeforeStart = ResponsesPublicStreamSession(webSearch: prepared)
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try finishBeforeStart.finish(
                responseJSON: responseData([:]),
                usage: .init(inputTokens: 0, outputTokens: 0)
            )
        }

        var invalidStatus = try coverageStartedPublicSession(prepared: prepared)
        invalidStatus.providerTurnActive = false
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try invalidStatus.finish(
                responseJSON: responseData(["status": "queued"]),
                usage: .init(inputTokens: 0, outputTokens: 0)
            )
        }

        var malformedFailure = try coverageStartedPublicSession(prepared: prepared)
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try malformedFailure.finish(
                responseJSON: responseData([
                    "id": "resp", "object": "response", "status": "failed",
                    "error": ["message": "no code"],
                ]),
                usage: .init(inputTokens: 0, outputTokens: 0)
            )
        }

        var officialFailure = try coverageStartedPublicSession(prepared: prepared)
        let failureFrames = try officialFailure.finish(
            responseJSON: responseData([
                "id": "resp", "object": "response", "status": "failed",
                "error": ["code": "private", "message": "private"],
            ]),
            usage: .init(inputTokens: 0, outputTokens: 0)
        )
        #expect(try publicEvents(failureFrames).map(\.name) == ["error", "response.failed"])

        var mismatchedTerminal = try coverageStartedPublicSession(prepared: prepared)
        mismatchedTerminal.providerTurnActive = false
        mismatchedTerminal.lastProviderTerminal = .incomplete
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try mismatchedTerminal.finish(
                responseJSON: responseData(
                    responseObject(
                        id: "resp",
                        createdAt: 1,
                        status: "completed",
                        output: [],
                        usage: .init(inputTokens: 0, outputTokens: 0)
                    )),
                usage: .init(inputTokens: 0, outputTokens: 0)
            )
        }

        var invalidFailureCode = ResponsesPublicStreamSession(webSearch: prepared)
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try invalidFailureCode.fail(code: "private", message: "private")
        }
    }
}

private func coverageStartedPublicSession(
    prepared: PreparedResponsesWebSearchRequest
) throws -> ResponsesPublicStreamSession {
    var session = ResponsesPublicStreamSession(webSearch: prepared)
    _ = try session.start(
        responseJSON: responseData(
            responseObject(
                id: "resp",
                createdAt: 1,
                status: "in_progress",
                output: [],
                usage: nil
            )))
    return session
}
