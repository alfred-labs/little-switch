import Foundation
import LittleSwitchSearch

/// The deliberately small, stateless MCP contract exposed by the gateway.
/// Parsing produces Sendable values before any provider work can suspend.
package enum WebSearchMCP {
    package static let protocolVersions = ["2025-06-18", "2025-11-25"]
    package static let currentProtocolVersion = "2025-11-25"

    package enum Identifier: Sendable {
        case string(String)
        case integer(Int64)

        var json: Any {
            switch self {
            case .string(let value): value
            case .integer(let value): value
            }
        }
    }

    package enum Operation: Sendable {
        case initialize(version: String)
        case ping
        case listTools
        case search(query: String)
    }

    package enum Message: Sendable {
        case notification
        case request(Identifier, Operation)
    }

    package struct Failure: Error {
        let code: Int
        let message: String
        var id: Identifier?
    }

    package static func parse(_ data: Data) throws(Failure) -> Message {
        // JSONSerialization also detects UTF-16/32. MCP permits only UTF-8;
        // unescaped NUL bytes cannot occur in valid UTF-8 JSON.
        guard !data.contains(0), String(data: data, encoding: .utf8) != nil,
            let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else {
            throw Failure(code: -32_700, message: "Parse error")
        }
        guard let object = value as? [String: Any] else {
            throw Failure(code: -32_600, message: "Invalid request")
        }
        let id: Identifier?
        if let rawID = object["id"] {
            id = try identifier(rawID)
        } else {
            id = nil
        }
        guard object["jsonrpc"] as? String == "2.0",
            let method = object["method"] as? String,
            object["params"] == nil || object["params"] is [String: Any]
        else {
            throw Failure(code: -32_600, message: "Invalid request", id: id)
        }
        // Notifications never execute tools, even if a client supplies a
        // request method without an ID. They are acknowledged at transport level.
        guard let id else { return .notification }
        let params = object["params"] as? [String: Any] ?? [:]
        let operation = try operation(method, params: params, id: id)
        return .request(id, operation)
    }

    private static func identifier(_ value: Any) throws(Failure) -> Identifier {
        if let string = value as? String { return .string(string) }
        guard let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.compare(NSNumber(value: number.int64Value)) == .orderedSame
        else {
            throw Failure(code: -32_600, message: "Invalid request ID")
        }
        return .integer(number.int64Value)
    }

    private static func operation(
        _ method: String, params: [String: Any], id: Identifier
    ) throws(Failure) -> Operation {
        switch method {
        case "initialize":
            guard let version = params["protocolVersion"] as? String,
                params["capabilities"] is [String: Any],
                let client = params["clientInfo"] as? [String: Any],
                client["name"] is String, client["version"] is String
            else {
                throw Failure(code: -32_602, message: "Invalid initialization parameters", id: id)
            }
            return .initialize(version: version)
        case "ping":
            return .ping
        case "tools/list":
            guard params["cursor"] == nil else {
                throw Failure(code: -32_602, message: "Unknown tools cursor", id: id)
            }
            return .listTools
        case "tools/call":
            // Keep the previous name callable for clients that cached the old catalog.
            guard let name = params["name"] as? String, ["search", "web_search"].contains(name) else {
                throw Failure(code: -32_602, message: "Unknown tool", id: id)
            }
            guard let arguments = params["arguments"] as? [String: Any],
                Set(arguments.keys) == ["query"],
                let query = arguments["query"] as? String,
                !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw Failure(code: -32_602, message: "\(name) requires a non-empty query string", id: id)
            }
            return .search(query: query)
        default:
            throw Failure(code: -32_601, message: "Method not found", id: id)
        }
    }

    package static func initialized(version: String) -> [String: Any] {
        [
            "protocolVersion": protocolVersions.contains(version) ? version : currentProtocolVersion,
            "capabilities": ["tools": [:]],
            "serverInfo": ["name": ProductIdentity.displayName, "version": ApplicationBuild.currentTag],
        ]
    }

    package static var catalog: [String: Any] {
        [
            "tools": [
                [
                    "name": "search",
                    "title": "Web search",
                    "description":
                        "Search the web for current information using the search provider configured in LittleSwitch. Returns source titles, URLs and snippets.",
                    "inputSchema": [
                        "type": "object",
                        "properties": ["query": ["type": "string", "minLength": 1, "description": "The search query"]],
                        "required": ["query"],
                        "additionalProperties": false,
                    ],
                    "outputSchema": [
                        "type": "object",
                        "properties": [
                            "results": [
                                "type": "array",
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "title": ["type": "string"],
                                        "url": ["type": "string"],
                                        "snippet": ["type": "string"],
                                    ],
                                    "required": ["title", "url", "snippet"],
                                ],
                            ]
                        ],
                        "required": ["results"],
                    ],
                    "annotations": ["readOnlyHint": true, "openWorldHint": true],
                ]
            ]
        ]
    }

    package static func searchResult(_ results: [WebSearchResult]) -> [String: Any] {
        let structured = [
            "results": results.map { ["title": $0.title, "url": $0.url, "snippet": $0.content] }
        ]
        // The JSON encoder always emits valid UTF-8.
        // swiftlint:disable:next optional_data_string_conversion
        let text = String(decoding: safeGatewayJSONData(structured), as: UTF8.self)
        return [
            "content": [["type": "text", "text": text]],
            "structuredContent": structured,
            "isError": false,
        ]
    }

    package static func toolError(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    package static func result(_ result: [String: Any], id: Identifier) -> Data {
        safeGatewayJSONData(["jsonrpc": "2.0", "id": id.json, "result": result])
    }

    package static func error(_ failure: Failure) -> Data {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": failure.code, "message": failure.message],
        ]
        if let id = failure.id { response["id"] = id.json }
        return safeGatewayJSONData(response)
    }
}
