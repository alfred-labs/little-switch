import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchSearch
import NIOCore

extension GatewayResponder {
    package func webSearchMCPResponse(_ request: Request, eventID: UUID) async throws -> Response {
        try Task.checkCancellation()
        if let response = WebSearchMCPHTTP.rejection(headers: request.headers) { return response }
        let body: ByteBuffer
        do {
            body = try await request.body.collect(upTo: min(maximumRequestBytes, 65_536))
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch is NIOTooManyBytesError {
            return WebSearchMCPHTTP.error(status: .contentTooLarge, message: "Request body is too large")
        } catch {
            return WebSearchMCPHTTP.error(status: .badRequest, message: "Could not read request body")
        }
        let message: WebSearchMCP.Message
        do {
            message = try WebSearchMCP.parse(Data(body.readableBytesView))
        } catch {
            return jsonResponse(
                status: error.code == -32_700 || error.code == -32_600 ? .badRequest : .ok,
                data: WebSearchMCP.error(error)
            )
        }
        switch message {
        case .notification:
            return Response(status: .accepted)
        // swift-format keeps bindings inside enum payloads.
        // swiftlint:disable:next pattern_matching_keywords
        case .request(let id, let operation):
            let result: [String: Any]
            switch operation {
            case .initialize(let version):
                result = WebSearchMCP.initialized(version: version)
            case .ping:
                result = [:]
            case .listTools:
                result = WebSearchMCP.catalog
            case .search(let query):
                result = try await webSearchMCPResult(query: query, eventID: eventID)
            }
            try Task.checkCancellation()
            return jsonResponse(status: .ok, data: WebSearchMCP.result(result, id: id))
        }
    }

    private func webSearchMCPResult(query: String, eventID: UUID) async throws -> [String: Any] {
        do {
            let capture = try await dependencies.snapshotCapturer.capture(state: state)
            try Task.checkCancellation()
            let configuration = capture.snapshot.webSearch
            guard configuration.provider != .disabled else {
                return WebSearchMCP.toolError(
                    "Web search is disabled. Enable a search provider in LittleSwitch Settings.")
            }
            let credential = try webSearchCredential(for: configuration)
            let attempt = try await executeWebSearch(
                query: query,
                configuration: configuration,
                credential: credential,
                options: WebSearchFilterOptions(),
                eventID: eventID
            )
            if let results = attempt.results { return WebSearchMCP.searchResult(results) }
            if let error = attempt.failure as? WebSearchProviderError, error == .missingCredential {
                return WebSearchMCP.toolError(
                    "Web search credential is missing. Configure it in LittleSwitch Settings.")
            }
            return WebSearchMCP.toolError(
                "Web search provider failed. Check the search provider in LittleSwitch Settings.")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return WebSearchMCP.toolError("Web search is unavailable. Check LittleSwitch Settings.")
        }
    }
}

private enum WebSearchMCPHTTP {
    static func rejection(headers: HTTPFields) -> Response? {
        let contentTypes = headers.filter { $0.name == .contentType }
        let contentType = contentTypes.first?.value.split(separator: ";").first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard contentTypes.count == 1, contentType == "application/json" else {
            return error(status: .unsupportedMediaType, message: "Content-Type must be application/json")
        }
        let accepted = headers.filter { $0.name == .accept }.flatMap { $0.value.split(separator: ",") }
        guard accepts("application/json", values: accepted), accepts("text/event-stream", values: accepted) else {
            return error(status: .notAcceptable, message: "Accept must include application/json and text/event-stream")
        }
        let versions = headers.filter { $0.name.canonicalName == "mcp-protocol-version" }.map(\.value)
        guard versions.isEmpty || (versions.count == 1 && WebSearchMCP.protocolVersions.contains(versions[0])) else {
            return error(status: .badRequest, message: "Unsupported MCP protocol version")
        }
        return nil
    }

    private static func accepts(_ type: String, values: [Substring]) -> Bool {
        values.contains { value in
            let parts = value.lowercased().split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.first == type else { return false }
            for parameter in parts.dropFirst() where parameter.hasPrefix("q=") {
                guard let quality = Double(parameter.dropFirst(2)), quality > 0, quality <= 1 else { return false }
            }
            return true
        }
    }

    static func error(status: HTTPResponse.Status, message: String) -> Response {
        jsonResponse(status: status, data: WebSearchMCP.error(.init(code: -32_600, message: message)))
    }
}
