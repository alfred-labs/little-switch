import AsyncHTTPClient
import CoreFoundation
import Foundation
import LittleSwitchTransport
import NIOHTTP1

package enum GatewayNativeCompactionRecoveryError: Error, Equatable {
    case needsAuthentication
    case invalidDiscovery
}

extension GatewayResponder {
    package func recoverNativeCompaction(
        body: Data, incomingHeaders: HTTPHeaders, eventID: UUID
    ) async throws -> Data {
        guard body.count <= maximumRequestBytes else { throw ResponsesCompactionError.invalidRequest }
        var original = try ResponsesCompactionJSON.object(body, error: .invalidRequest)
        guard var input = original["input"] as? [[String: Any]],
            input.contains(where: { $0["type"] as? String == "compaction" })
        else { throw ResponsesCompactionError.invalidRequest }
        let trigger = input.last?["type"] as? String == "compaction_trigger" ? input.removeLast() : nil
        guard !input.contains(where: { $0["type"] as? String == "compaction_trigger" }) else {
            throw ResponsesCompactionError.invalidRequest
        }
        let headers = try NativeCompactionDiscovery.authenticatedHeaders(incomingHeaders)
        var native = original
        native["model"] = try await discoverCompactionModel(headers: headers)
        native["stream"] = true
        native["input"] = input + [["type": "compaction_trigger"]]
        // Generation settings belong to the selected custom model. Let the
        // native model use its own defaults for this internal summary turn.
        for key in ["reasoning", "temperature", "top_p", "max_output_tokens"] { native.removeValue(forKey: key) }
        guard let plan = try ResponsesCompactionPlan.prepare(body: dependencies.serializer.encodeJSONObject(native))
        else {
            throw ResponsesCompactionError.invalidRequest
        }
        let result = try await compactResponses(
            plan: plan.retainingProviderState(),
            target: .native,
            incomingHeaders: headers,
            eventID: eventID
        )
        let item = try ResponsesCompactionJSON.object(result.itemJSON, error: .invalidResponse)
        original["input"] = [item] + (trigger.map { [$0] } ?? [])
        let recovered = try dependencies.serializer.encodeJSONObject(original)
        guard recovered.count <= maximumRequestBytes else { throw ResponsesCompactionError.invalidRequest }
        return recovered
    }

    private func discoverCompactionModel(headers: HTTPHeaders) async throws -> String {
        let accountSession = !headers["chatgpt-account-id"].isEmpty
        let query =
            accountSession ? NativeCompactionDiscovery.clientVersion(headers).map { "client_version=\($0)" } : nil
        let url = try EndpointURL.appending(
            "models",
            percentEncodedQuery: query,
            to: accountSession ? CodexNativePassthrough.chatGPTBaseURL : CodexNativePassthrough.openAIBaseURL
        )
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .GET
        request.headers = headers
        request.headers.replaceOrAdd(name: "accept", value: "application/json")
        try Task.checkCancellation()
        let response = try await transport.execute(request)
        try Task.checkCancellation()
        let succeeded = (200..<300).contains(response.status.code)
        let bytes: Data
        do {
            bytes = try await Data(response.body.collect(upTo: maximumErrorBytes).readableBytesView)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if !succeeded { throw CompactionUpstreamFailure(response: response, body: Data()) }
            throw GatewayNativeCompactionRecoveryError.invalidDiscovery
        }
        try Task.checkCancellation()
        guard succeeded else { throw CompactionUpstreamFailure(response: response, body: bytes) }
        return try NativeCompactionDiscovery.model(in: bytes, accountSession: accountSession)
    }
}

private enum NativeCompactionDiscovery {
    private struct Candidate {
        let id: String
        let priority: Int
        let index: Int
    }

    /// Only native authentication and session metadata belong on this request.
    /// Provider keys, cookies, and arbitrary custom headers never cross over.
    private static let headerNames: Set<String> = [
        "authorization", "chatgpt-account-id", "user-agent", "openai-organization", "openai-project", "openai-beta",
        "originator", "session_id", "conversation_id", "x-codex-turn-metadata", "x-codex-parent-thread-id", "version",
    ]

    static func authenticatedHeaders(_ incoming: HTTPHeaders) throws -> HTTPHeaders {
        var headers = HTTPHeaders()
        for header in CodexNativePassthrough.forwardedHeaders(incoming)
        where headerNames.contains(header.name.lowercased()) {
            headers.add(name: header.name, value: header.value)
        }
        let authorizations = headers["authorization"]
        guard authorizations.count == 1 else { throw GatewayNativeCompactionRecoveryError.needsAuthentication }
        let parts = authorizations[0].split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, parts[0].lowercased() == "bearer",
            parts[1].lowercased() != CodexNativePassthrough.sentinelAPIKey
        else { throw GatewayNativeCompactionRecoveryError.needsAuthentication }
        return headers
    }

    static func clientVersion(_ headers: HTTPHeaders) -> String? {
        // The CLI agent carries `codex-cli/0.154.0`, but the Desktop agent
        // spells it `Codex Desktop/0.153.4 (…)`: the bare word carries no
        // version and the number rides on the `Desktop` token. The `version`
        // header Codex itself sends on every request covers both shapes.
        let versionHeader = headers["version"].compactMap { validClientVersion(String($0)) }
        if let version = versionHeader.first {
            return version
        }
        for value in headers["user-agent"] {
            for token in value.split(whereSeparator: \.isWhitespace) {
                let parts = token.split(separator: "/", omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                let name = parts[0].lowercased()
                guard name.hasPrefix("codex") || name == "desktop" else { continue }
                if let version = validClientVersion(String(parts[1])) {
                    return version
                }
            }
        }
        return nil
    }

    private static func validClientVersion(_ raw: String) -> String? {
        let version = raw.prefix { $0.isNumber || $0 == "." }
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        let valid =
            components.count == 3
            && components.allSatisfy { component in
                !component.isEmpty && component.utf8.allSatisfy { (48...57).contains($0) }
            }
        return valid ? String(version) : nil
    }

    static func model(in data: Data, accountSession: Bool) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let models = root[accountSession ? "models" : "data"] as? [[String: Any]]
        else { throw GatewayNativeCompactionRecoveryError.invalidDiscovery }
        let candidates = models.enumerated().compactMap { index, model -> Candidate? in
            guard let id = ResponsesCompactionJSON.nonempty(model[accountSession ? "slug" : "id"]),
                isConversationModel(id, metadata: model, accountSession: accountSession)
            else { return nil }
            let priority =
                (model["priority"] as? NSNumber).flatMap {
                    CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0 as? Int
                } ?? Int.max
            return Candidate(id: id, priority: priority, index: index)
        }
        let selected = candidates.min {
            $0.priority == $1.priority ? $0.index < $1.index : $0.priority < $1.priority
        }
        guard let selected else { throw GatewayNativeCompactionRecoveryError.invalidDiscovery }
        return selected.id
    }

    private static func isConversationModel(_ id: String, metadata: [String: Any], accountSession: Bool) -> Bool {
        let filtered = OpenAIModelDiscoveryFilter.filtered(
            [DiscoveredModel(id: id)], baseURL: CodexNativePassthrough.openAIBaseURL)
        let lowered = id.lowercased()
        let specialized: Set<String> = ["audio", "realtime", "transcribe", "search", "research", "image", "embedding"]
        guard !filtered.isEmpty, !lowered.split(separator: "-").contains(where: { specialized.contains(String($0)) })
        else { return false }
        if let modalities = metadata["input_modalities"] as? [String], !modalities.contains("text") { return false }
        if accountSession { return metadata["visibility"] as? String == "list" }
        // The API catalog exposes identifiers rather than Codex capabilities.
        // Admit conversation/coding families, never a fallback model alias.
        if lowered.hasPrefix("gpt-") {
            return Int(lowered.dropFirst(4).prefix(while: \.isNumber)).map { $0 >= 4 } ?? false
        }
        if lowered.hasPrefix("codex-") { return true }
        return lowered.hasPrefix("o")
            && Int(lowered.dropFirst().split(separator: "-").first ?? "").map { $0 > 0 } == true
    }
}
