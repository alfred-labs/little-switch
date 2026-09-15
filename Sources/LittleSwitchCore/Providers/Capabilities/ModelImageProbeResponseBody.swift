import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore

/// Accepts providers that ignore stream:false, without confusing partial text for a final answer.
enum ModelImageProbeResponseBody {
    enum Error: Swift.Error { case incomplete, invalid }

    static func fields(body: Data, wire: ModelImageInputWire) throws -> [String: Any] {
        if let root = try? WireJSONCompatibility.fields(body) { return root }
        guard let text = String(data: body, encoding: .utf8), text.contains("data:") else { throw Error.invalid }
        var decoder = ServerSentEventDecoder(maximumFrameBytes: ModelImageProbeResponse.maximumBytes)
        let frames: [ServerSentEventFrame]
        do {
            frames = try decoder.append(ByteBuffer(bytes: body)) + decoder.finish()
        } catch ServerSentEventDecoder.Error.incompleteFrame {
            throw Error.incomplete
        }
        var final: [String: Any]?
        var answer = ""
        var reason: String?
        var usage: [String: Any]?
        var done = false
        for frame in frames {
            guard !done else { throw Error.invalid }
            if frame.terminal {
                done = true
                continue
            }
            let root = try WireJSONCompatibility.fields(frame.data)
            guard root["error"] == nil || root["error"] is NSNull,
                frame.event != "error", root["type"] as? String != "error"
            else {
                throw Error.invalid
            }
            if wire == .responses {
                guard final == nil else { throw Error.invalid }
                let event = frame.event ?? root["type"] as? String
                final = try responsesTerminal(root, event: event)
            } else {
                if let value = root["usage"] as? [String: Any] { usage = value }
                guard let choices = root["choices"] as? [[String: Any]], choices.count <= 1 else { throw Error.invalid }
                guard let choice = choices.first else { continue }
                guard reason == nil else { throw Error.invalid }
                if let delta = choice["delta"] as? [String: Any], let content = delta["content"] as? String {
                    answer += content
                }
                if let finish = choice["finish_reason"] as? String { reason = finish }
            }
        }
        if wire == .responses {
            guard let final else { throw Error.incomplete }
            return final
        }
        guard done, let reason else { throw Error.incomplete }
        var root: [String: Any] = [
            "choices": [["finish_reason": reason, "message": ["role": "assistant", "content": answer]]]
        ]
        if let usage { root["usage"] = usage }
        return root
    }

    private static func responsesTerminal(_ root: [String: Any], event: String?) throws -> [String: Any]? {
        guard event == "response.completed" || event == "response.incomplete" || event == "response.failed" else {
            return nil
        }
        let response = root["response"] as? [String: Any] ?? root
        guard let status = response["status"] as? String, event == "response.\(status)" else { throw Error.invalid }
        if let type = root["type"] as? String, type != event { throw Error.invalid }
        return response
    }
}
