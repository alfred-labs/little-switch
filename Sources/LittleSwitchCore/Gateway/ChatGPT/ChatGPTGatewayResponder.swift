import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore

package struct ChatGPTGatewayResponder: HTTPResponder {
    package typealias Context = BasicRequestContext

    let state: GatewayState
    let transport: any UpstreamTransport
    let secretStore: any SecretStore
    let requiredAuthorityPort: Int?
    let history: ChatGPTHistoryStore?
    let activeTurns: ChatGPTActiveTurns
    let trafficRecorder: any TrafficRecording
    let monitoring: GatewayMonitoring?

    package init(
        state: GatewayState,
        transport: any UpstreamTransport,
        secretStore: any SecretStore,
        requiredAuthorityPort: Int? = ChatGPTLaunchEnvironment.port,
        history: ChatGPTHistoryStore? = nil,
        activeTurns: ChatGPTActiveTurns = ChatGPTActiveTurns(),
        trafficRecorder: any TrafficRecording = NoopTrafficRecorder(),
        monitoring: GatewayMonitoring? = nil
    ) {
        self.state = state
        self.transport = transport
        self.secretStore = secretStore
        self.requiredAuthorityPort = requiredAuthorityPort
        self.history = history
        self.activeTurns = activeTurns
        self.trafficRecorder = trafficRecorder
        self.monitoring = monitoring
    }

    package func respond(to request: Request, context: Context) async throws -> Response {
        guard let authority = request.head.authority,
            GatewaySecurity.isAllowedAuthority(authority, requiredPort: requiredAuthorityPort),
            request.headers[.origin] == nil || request.headers[.origin] == "https://chatgpt.com"
        else { return try errorResponse(.forbidden, "A local ChatGPT request is required") }
        guard let url = try? ChatGPTRequestBoundary.upstreamURL(path: request.uri.string) else {
            return try errorResponse(.notFound, "Unknown ChatGPT endpoint")
        }
        let body: Data
        do {
            body = Data(try await request.body.collect(upTo: 64 * 1_024 * 1_024).readableBytesView)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try errorResponse(.contentTooLarge, "ChatGPT request is too large")
        }
        do {
            let snapshot = await state.capture()
            let models = Set(snapshot.codex.exposedModels(in: snapshot.providers).map(CodexCatalog.slug))
            let route = try ChatGPTManagedRoute.resolve(
                path: request.uri.string,
                method: request.method,
                body: body,
                models: models
            )
            if let response = try await managedResponse(route, request: request, context: context) { return response }
            if let response = try await historyListResponse(request, url: url, body: body) { return response }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try managedErrorResponse(error)
        }
        do {
            let upstream = try await transport.execute(nativeRequest(request, url: url, body: body))
            if [301, 302, 303, 307, 308].contains(upstream.status.code) {
                return try errorResponse(.badGateway, "The ChatGPT backend requested an unsupported redirect")
            }
            guard isCatalog(request), upstream.status == .ok else { return nativeResponse(upstream) }
            let snapshot = await state.capture()
            let models = snapshot.codex.exposedModels(in: snapshot.providers).map {
                ChatGPTCatalogModel(slug: CodexCatalog.slug(for: $0), title: $0.displayName)
            }
            let bytes = Data(try await upstream.body.collect(upTo: 8 * 1_024 * 1_024).readableBytesView)
            let merged = try ChatGPTCatalog.merge(nativeData: bytes, models: models)
            return nativeJSONResponse(merged, headers: upstream.headers)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try errorResponse(.badGateway, "The ChatGPT backend response could not be read")
        }
    }
}
