import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import NIOHTTP1

/// Probes whether a provider's Responses route serves namespaced tools with
/// one bounded behavioral request at save time.
///
/// Unlike the wire probe's zero-token `{}`, namespace support cannot be read
/// from a validation rejection alone — a lenient front door accepts any
/// shape — so this probe spends one tiny forced generation: a namespace
/// declaration `ls_probe` with the child `ping`, a pair `tool_choice` that
/// forces the call, and a 16-token cap. The verdict classifies what came
/// back; every inconclusive answer (auth wall, quota, 5xx, transport error,
/// unreadable body) stays `.unknown` so a probe never becomes routing
/// evidence. Throws only on cancellation.
public struct ProviderNamespaceProber: ProviderNamespaceProbing {
    /// Probe-grade, not traffic-grade: a host that accepts TCP but never
    /// answers must not hold a save hostage.
    private static let probeTimeout = TimeAmount.seconds(8)
    private static let maximumBodyBytes = 16 * 1_024

    private let transport: any UpstreamTransport

    public init(transport: any UpstreamTransport) {
        self.transport = transport
    }

    public func probe(
        provider: Provider,
        secret: String?,
        model: String
    ) async throws -> ProviderNamespaceProbe {
        do {
            let request = try ProviderRequestBuilder.forwarding(
                api: .responses,
                provider: provider,
                secret: secret,
                headers: HTTPHeaders([("content-type", "application/json")]),
                body: Self.requestBody(model: model)
            )
            let response = try await transport.execute(request, timeout: Self.probeTimeout)
            let body = (try? await response.body.collect(upTo: Self.maximumBodyBytes))
                .map { Data($0.readableBytesView) }
            return ProviderNamespaceProbe(
                verdict: Self.verdict(status: UInt(response.status.code), body: body),
                model: model,
                date: Date()
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ProviderNamespaceProbe(verdict: .unknown, model: model, date: Date())
        }
    }

    /// The probe declaration: a namespace the gateway itself would flatten,
    /// forced through the native pair form only a namespace-aware backend
    /// can answer.
    private static func requestBody(model: String) -> Data {
        let object: [String: Any] = [
            "model": model,
            "input": "Call the probe tool.",
            "tools": [
                [
                    "type": "namespace",
                    "name": "ls_probe",
                    "description": "LittleSwitch namespace probe.",
                    "tools": [
                        [
                            "type": "function",
                            "name": "ping",
                            "description": "Answer the probe.",
                            "parameters": ["type": "object", "properties": [:]],
                        ]
                    ],
                ]
            ],
            "tool_choice": ["type": "function", "name": "ping", "namespace": "ls_probe"],
            "max_output_tokens": 16,
            "stream": false,
        ]
        // A dictionary of string, integer, and boolean literals always
        // serializes; the failure mode does not exist to handle.
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// A shape rejection is a 4xx the request could fix by not being itself:
    /// auth, payment, proxy, timeout, and rate-limit answers say nothing
    /// about the namespace shape and stay unknown, like the wire probe.
    private static func verdict(status: UInt, body: Data?) -> ProviderNamespaceVerdict {
        switch status {
        case 200..<300:
            guard let body else {
                return .unknown
            }
            return verdict(body: body)
        case 401, 402, 403, 407, 408, 429:
            return .unknown
        case 400..<500:
            return .rejected
        default:
            return .unknown
        }
    }

    private static func verdict(body: Data) -> ProviderNamespaceVerdict {
        guard
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let output = object["output"] as? [[String: Any]]
        else {
            return .unknown
        }
        // The pair form is the native answer; the bare child and the
        // flattened spellings are backends that serve the tool under a
        // naming of their own — all three make the namespace tools callable.
        let called = output.contains { item in
            guard item["type"] as? String == "function_call",
                let name = item["name"] as? String
            else {
                return false
            }
            let namespace = item["namespace"] as? String
            switch name {
            case "ping":
                return namespace == nil || namespace == "ls_probe"
            case "ls_probe__ping":
                return namespace == nil
            default:
                return false
            }
        }
        return called ? .restored : .silentlyDropped
    }
}
