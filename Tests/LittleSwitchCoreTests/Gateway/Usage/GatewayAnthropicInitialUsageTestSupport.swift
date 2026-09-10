import AsyncHTTPClient
import Foundation
import LittleSwitchTransport

@testable import LittleSwitchCore

actor GatewayInitialUsageResolverProbe: AnthropicInitialUsageResolving {
    enum Mode: Sendable {
        case fixed(AnthropicInitialUsageResolution)
        case gated(GatewayExecutionGate, AnthropicInitialUsageResolution)
        case cancellation
        case forbidden
    }

    private let mode: Mode
    private(set) var requests: [AnthropicInitialUsageRequestContext] = []

    init(mode: Mode) {
        self.mode = mode
    }

    var callCount: Int { requests.count }

    func estimate(
        request: AnthropicInitialUsageRequestContext,
        transport: any UpstreamTransport
    ) async throws -> AnthropicInitialUsageResolution {
        _ = transport
        requests.append(request)
        switch mode {
        case .fixed(let resolution):
            return resolution
        // swiftlint:disable:next pattern_matching_keywords
        case .gated(let gate, let resolution):
            try await gate.enter()
            return resolution
        case .cancellation:
            throw CancellationError()
        case .forbidden:
            throw GatewayTestError.failure
        }
    }
}

func gatewayInitialUsageUTF8<Bytes: Collection>(_ bytes: Bytes) -> String
where Bytes.Element == UInt8 {
    guard let string = String(bytes: bytes, encoding: .utf8) else {
        preconditionFailure("Expected a valid UTF-8 gateway test fixture")
    }
    return string
}
