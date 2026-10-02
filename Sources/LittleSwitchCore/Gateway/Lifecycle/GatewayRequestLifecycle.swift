import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchCommon

extension GatewayResponder {
    public func respond(to request: Request, context: Context) async throws -> Response {
        _ = context
        return try await respond(to: request)
    }

    /// WebSocket turns enter the same lifecycle without a second loopback request.
    package func respond(to request: Request) async throws -> Response {
        let eventID = UUID()
        let external = !ProductIdentity.isInternalGatewayPath(request.uri.path)
        let recordsTraffic = external || GatewayRoute.resolve(request.uri.path) == .webSearchMCP
        let observation =
            external ? await monitoring?.begin(requestID: eventID, route: .gatewayPath(request.uri.path)) : nil
        var selected = self
        if !recordsTraffic { selected.trafficRecorder = NoopTrafficRecorder() }
        let responder = selected
        let monitoringPath = [ProductIdentity.gatewayMetricsPath, ProductIdentity.gatewayLogsPath].contains(
            request.uri.path)
        return try await GatewayMonitoringScope.$current.withValue(observation) {
            var response = try await responder.respondRecording(
                request, eventID: eventID, observation: observation, recordsTraffic: recordsTraffic)
            if monitoringPath {
                response.headers[.cacheControl] = "no-store"
            }
            return response
        }
    }

    private func respondRecording(
        _ request: Request, eventID: UUID, observation: MonitoringRequestContext?, recordsTraffic: Bool
    ) async throws -> Response {
        let permitCompletion = GatewayPermitCompletionGuard(
            state: state,
            eventID: eventID,
            monitoring: observation
        )
        if recordsTraffic {
            trafficRecorder.record(
                eventID: eventID,
                action: .started(
                    TrafficRequestStart(
                        startedAt: Date(),
                        method: request.method.rawValue,
                        path: request.uri.path,
                        headers: TrafficRedactor.headers(request.headers)
                    )
                )
            )
        }
        do {
            try Task.checkCancellation()
            let response: Response
            var terminalFailure: TrafficFailure?
            do {
                response = try await routeResponse(request, eventID: eventID)
            } catch let failure as GatewayUpstreamRequestFailure {
                let message = failure.message(eventID: eventID)
                response = openAIError(status: .badGateway, message: message)
                terminalFailure = TrafficFailure(kind: "transport", message: message)
            }
            // Cancellation still wins if the transport threw another error
            // while this task was being cancelled.
            try Task.checkCancellation()
            return finalizingResponse(
                response,
                eventID: eventID,
                permitCompletion: permitCompletion,
                recordsTraffic: recordsTraffic,
                terminalFailure: terminalFailure
            )
        } catch let failure as HandledAdmissionFailure {
            await permitCompletion.finish()
            let handled = admissionFailureResponse(failure)
            return finalizingResponse(
                handled.response,
                eventID: eventID,
                permitCompletion: permitCompletion,
                recordsTraffic: recordsTraffic,
                terminalFailure: handled.terminalFailure
            )
        } catch is CancellationError {
            await observation?.finish(error: .cancelled)
            await permitCompletion.finish()
            trafficRecorder.record(eventID: eventID, action: .cancelled(finishedAt: Date()))
            throw CancellationError()
        } catch {
            await observation?.finish(error: .transport)
            await permitCompletion.finish()
            trafficRecorder.record(
                eventID: eventID,
                action: .failed(
                    TrafficFailureCompletion(
                        status: nil,
                        finishedAt: Date(),
                        failure: TrafficFailure(
                            kind: "gateway",
                            message: "Gateway response failed"
                        )
                    )
                )
            )
            throw error
        }
    }

}
