import Foundation
import Testing

@testable import LittleSwitchCore

enum ResponsesBufferedTerminalCase: String, CaseIterable, Sendable {
    case nativeCompleted, nativeLength, nativeFiltered, nativeContextLimit, nativeFailure
    case chatCompleted, chatLength, chatFiltered, chatContextLimit, chatFailure

    var supportsNative: Bool { rawValue.hasPrefix("native") }

    var status: String {
        switch self {
        case .nativeCompleted, .chatCompleted: "completed"
        case .nativeLength, .nativeFiltered, .chatLength, .chatFiltered: "incomplete"
        case .nativeContextLimit, .nativeFailure, .chatContextLimit, .chatFailure: "failed"
        }
    }

    var incompleteReason: String? {
        switch self {
        case .nativeLength, .chatLength: "max_output_tokens"
        case .nativeFiltered, .chatFiltered: "content_filter"
        default: nil
        }
    }

    var errorCode: String? {
        switch self {
        case .nativeContextLimit, .chatContextLimit: "context_length_exceeded"
        case .nativeFailure, .chatFailure: "server_error"
        default: nil
        }
    }

    private var finishReason: String {
        switch self {
        case .nativeCompleted, .chatCompleted: "stop"
        case .nativeLength, .chatLength: "length"
        case .nativeFiltered, .chatFiltered: "sensitive"
        case .nativeContextLimit, .chatContextLimit: "model_context_window_exceeded"
        case .nativeFailure, .chatFailure: "network_error"
        }
    }

    func body(privateSearchCall: Bool = false) throws -> Data {
        if supportsNative {
            var output: [[String: Any]] = [
                [
                    "id": "msg_partial", "type": "message", "role": "assistant",
                    "status": status == "completed" ? "completed" : "incomplete",
                    "content": [["type": "output_text", "text": "Partial answer", "annotations": []]],
                ]
            ]
            if privateSearchCall {
                output.append(
                    functionCallItem(
                        id: "fc_partial",
                        callID: "call_partial",
                        name: "web_search",
                        arguments: #"{"query":"Swift"}"#,
                        status: "completed"
                    ))
            }
            return try responseData([
                "id": "resp_limit", "object": "response", "created_at": 1,
                "model": "glm-5.2", "status": status, "output": output,
                "incomplete_details": incompleteReason.map {
                    ["reason": $0, "provider_private": "provider-private-details"]
                } as Any? ?? NSNull(),
                "error": errorCode.map {
                    [
                        "code": $0 == "server_error" ? "provider_private_code" : $0,
                        "message": "provider-private-error", "provider_private": "provider-private-error-metadata",
                    ]
                } as Any? ?? NSNull(),
                "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            ])
        }
        var message: [String: Any] = ["role": "assistant", "content": "Partial answer"]
        if privateSearchCall {
            message["tool_calls"] = [
                [
                    "id": "call_partial", "type": "function",
                    "function": ["name": "web_search", "arguments": #"{"query":"Swift"}"#],
                ]
            ]
        }
        return try responseData([
            "id": "chatcmpl_limit", "created": 1,
            "choices": [["finish_reason": finishReason, "message": message]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2],
        ])
    }

    func expectTerminal(_ response: [String: Any]) throws {
        #expect(response["status"] as? String == status)
        if let incompleteReason {
            #expect(response["incomplete_details"] as? [String: String] == ["reason": incompleteReason])
        } else {
            #expect(response["incomplete_details"] is NSNull)
        }
        if let errorCode {
            #expect(
                response["error"] as? [String: String] == [
                    "code": errorCode, "message": "Internal server error",
                ])
        } else {
            #expect(response["error"] == nil || response["error"] is NSNull)
        }
        #expect(try !#require(String(data: responseData(response), encoding: .utf8)).contains("provider-private"))
    }
}

enum ResponsesBufferedAdaptation: CaseIterable, Sendable {
    case namespace
    case discovery
    case refusedSearch

    var tools: [[String: Any]] {
        if self == .discovery {
            return [
                [
                    "type": "tool_search", "execution": "client", "description": "Find tools.",
                    "parameters": ["type": "object", "properties": ["goal": ["type": "string"]]],
                ]
            ]
        }
        let namespace: [String: Any] = [
            "type": "namespace", "name": "files",
            "tools": [["type": "function", "name": "read_file", "parameters": ["type": "object"]]],
        ]
        return self == .refusedSearch
            ? [["type": "web_search", "external_web_access": false], namespace]
            : [namespace]
    }
}
