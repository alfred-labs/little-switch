import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchTransport

/// A synthetic, bounded witness. No client prompt, history or tool implementation is executed.
package struct CustomToolCapabilityProber: Sendable {
    private let transport: any UpstreamTransport
    private let waitForDeadline: @Sendable () async throws -> Void

    package init(
        transport: any UpstreamTransport,
        waitForDeadline: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(15)) }
    ) {
        self.transport = transport
        self.waitForDeadline = waitForDeadline
    }

    package func probe(
        template: HTTPClientRequest, modelID: String, wire: ProviderToolContract.Wire
    ) async throws -> CustomToolCapabilityMode {
        try Task.checkCancellation()
        guard wire != .anthropic else { return .inconclusive }
        let marker = "ls_probe_" + UUID().uuidString
        let native = try await witness(
            template: template, modelID: modelID, wire: wire, marker: marker, envelope: false)
        switch native {
        case .matched: return .native
        case .inconclusive, .optionalControlRejected: return .inconclusive
        case .unusable:
            let fallback = try await witness(
                template: template, modelID: modelID, wire: wire, marker: marker, envelope: true)
            return fallback == .matched ? .functionEnvelope : .inconclusive
        }
    }

    private func witness(
        template: HTTPClientRequest, modelID: String, wire: ProviderToolContract.Wire, marker: String, envelope: Bool
    ) async throws -> CustomToolCapabilityResponse.Outcome {
        try Task.checkCancellation()
        let request = try CustomToolCapabilityRequest.make(
            template: template, modelID: modelID, wire: wire, marker: marker, envelope: envelope)
        let optionalControl = CustomToolCapabilityRequest.optionalControl(template: template, wire: wire)
        let outcome = try await withThrowingTaskGroup(of: CustomToolCapabilityResponse.Outcome.self) { group in
            group.addTask {
                let first = try await perform(
                    request: request, wire: wire, marker: marker, envelope: envelope, optionalControl: optionalControl)
                guard first == .optionalControlRejected else { return first }
                let retry = try CustomToolCapabilityRequest.make(
                    template: template,
                    modelID: modelID,
                    wire: wire,
                    marker: marker,
                    envelope: envelope,
                    includeOptionalControl: false)
                return try await perform(
                    request: retry, wire: wire, marker: marker, envelope: envelope, optionalControl: nil)
            }
            group.addTask {
                try await waitForDeadline()
                return .inconclusive
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
        try Task.checkCancellation()
        return outcome
    }

    private func perform(
        request: HTTPClientRequest,
        wire: ProviderToolContract.Wire,
        marker: String,
        envelope: Bool,
        optionalControl: String?
    ) async throws -> CustomToolCapabilityResponse.Outcome {
        do {
            let response = try await transport.execute(request, timeout: .seconds(15))
            var body = Data()
            for try await buffer in response.body {
                try Task.checkCancellation()
                guard buffer.readableBytes <= CustomToolCapabilityResponse.maximumBytes - body.count else {
                    return .inconclusive
                }
                body.append(contentsOf: buffer.readableBytesView)
            }
            return CustomToolCapabilityResponse.classify(
                body: body,
                status: Int(clamping: response.status.code),
                wire: wire,
                marker: marker,
                envelope: envelope,
                optionalControl: optionalControl)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return .inconclusive
        }
    }
}
