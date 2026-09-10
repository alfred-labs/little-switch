import Foundation
import HTTPTypes
import Hummingbird
import NIOCore

extension MonitoringRoute {
    package static func gatewayPath(_ path: String) -> Self {
        switch GatewayRoute.resolve(path) {
        case .messages: .messages
        case .responses: .responses
        case .countTokens: .countTokens
        case .models: .models
        default: .unknown
        }
    }
}

extension GatewayResponder {
    package func monitoringResponse(_ request: Request, route: GatewayRoute) async throws -> Response {
        guard let monitoring else { return Response(status: .notFound) }
        let configuration = await monitoring.configuration()
        guard route == .metrics ? configuration.exposeMetrics : configuration.exposeLogs else {
            return Response(status: .notFound)
        }
        guard request.method == .get else {
            return Response(status: .methodNotAllowed, headers: [.allow: "GET"])
        }
        if route == .metrics {
            let accept = request.headers.filter { $0.name == .accept }.map(\.value)
            guard let format = MonitoringMetricsTextEncoder.negotiate(accept: accept) else {
                return Response(status: .notAcceptable)
            }
            let snapshot = await monitoring.store.snapshot(providerPool: state.requestPoolSnapshot())
            return Response(
                status: .ok,
                headers: [.contentType: format.contentType],
                body: .init(byteBuffer: .init(string: MonitoringMetricsTextEncoder.encode(snapshot, format: format))))
        }
        do {
            let components = URLComponents(string: request.uri.string)
            let query = try MonitoringLogQuery(parameters: components?.queryItems ?? [])
            let page = try await monitoring.store.logs(query: query)
            return jsonResponse(status: .ok, data: try page.encoded())
        } catch MonitoringLogQueryError.cursorExpired {
            return jsonResponse(
                status: .gone,
                data: Data(
                    #"{"schemaVersion":1,"error":"cursor_expired","retentionLost":true,"restartRequired":true}"#.utf8))
        } catch {
            return jsonResponse(status: .badRequest, data: Data(#"{"schemaVersion":1,"error":"invalid_query"}"#.utf8))
        }
    }

    package func finalizingResponse(
        _ response: Response,
        eventID: UUID,
        permitCompletion: GatewayPermitCompletionGuard,
        recordsTraffic: Bool,
        terminalFailure: TrafficFailure? = nil
    ) -> Response {
        if recordsTraffic {
            return recordingClientResponse(
                response, eventID: eventID, permitCompletion: permitCompletion, terminalFailure: terminalFailure)
        }
        let originalBody = response.body
        return Response(
            status: response.status,
            headers: response.headers,
            body: .init(contentLength: originalBody.contentLength) { writer in
                do {
                    try await originalBody.write(writer)
                    await permitCompletion.finish()
                } catch {
                    await permitCompletion.finish()
                    throw error
                }
            })
    }
}
