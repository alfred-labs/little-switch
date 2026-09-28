import Foundation
import NIOCore
import NIOHTTP1
import NIOSSL
import NIOTransportServices

enum WebSocketClientBootstrap {
    static func connect(
        request: UpstreamWebSocketRequest,
        configuration: UpstreamWebSocketConfiguration,
        tlsContext: NIOSSLContext,
        control: WebSocketConnectionControl
    ) async throws -> WebSocketUpgradeOutcome {
        guard let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false),
            let componentHost = components.host
        else { throw UpstreamWebSocketFailure(kind: .invalidRequest) }
        let host = componentHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let secure = components.scheme?.lowercased() == "wss"
        let port = components.port ?? (secure ? 443 : 80)
        // IP literals are verified against the peer certificate's IP SAN. RFC 6066
        // forbids them in SNI; a nil hostname retains NIOSSL's peer-IP verification.
        let serverHostname = (try? SocketAddress(ipAddress: host, port: port)) == nil ? host : nil
        var headers = request.headers
        let httpHost = host.contains(":") ? "[\(host)]" : host
        headers.add(name: "Host", value: port == (secure ? 443 : 80) ? httpHost : "\(httpHost):\(port)")
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        let target = path + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
        let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: target, headers: headers)
        let connecting = control.eventLoop.flatSubmit {
            control.state.value.armHandshakeDeadline(control: control)
            return NIOTSConnectionBootstrap(group: control.eventLoop)
                .connectTimeout(configuration.handshakeTimeout.webSocketTimeAmount)
                .channelOption(NIOTSChannelOptions.waitForActivity, value: false)
                .channelOption(NIOTSChannelOptions.maximumReceiveLength, value: 8 * 1_024)
                .channelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        try control.state.value.register(channel)
                        if secure {
                            let tls = try NIOSSLClientHandler(context: tlsContext, serverHostname: serverHostname)
                            try channel.pipeline.syncOperations.addHandler(tls)
                            control.state.value.tlsCloseContext = try channel.pipeline.syncOperations.context(
                                handler: tls)
                        }
                        try WebSocketUpgradeHandler.configure(
                            channel: channel, request: head, control: control, configuration: configuration)
                    }
                }
                .connect(host: host, port: port)
        }
        _ = try await connecting.get()
        return try await control.handshake.get()
    }
}
