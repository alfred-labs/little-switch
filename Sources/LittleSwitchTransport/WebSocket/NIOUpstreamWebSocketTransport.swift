import Foundation
import NIOSSL
import NIOTransportServices

public actor NIOUpstreamWebSocketTransport: UpstreamWebSocketTransport {
    private let identity = UUID()
    private let configuration: UpstreamWebSocketConfiguration
    private let tlsContext: NIOSSLContext
    private var connections: [UUID: WebSocketConnectionControl] = [:]
    private var stopped = false
    private var shutdownWaiters: [CheckedContinuation<Void, Never>] = []

    /// The client trust configuration defaults to the platform trust store, as
    /// for the HTTP transport; callers may pin explicit trust roots instead.
    public init(
        configuration: UpstreamWebSocketConfiguration = .init(),
        tlsConfiguration: TLSConfiguration = .makeClientConfiguration()
    ) throws {
        try configuration.validate()
        self.configuration = configuration
        self.tlsContext = try NIOSSLContext(configuration: tlsConfiguration)
    }

    public func withConnection(
        _ request: UpstreamWebSocketRequest,
        operation: @escaping @Sendable (UpstreamWebSocketConnection) async throws -> Void
    ) async throws {
        try Task.checkCancellation()
        guard !stopped else { throw UpstreamWebSocketFailure(kind: .transportShutDown) }
        let identifier = UUID()
        let control = WebSocketConnectionControl(
            eventLoop: NIOTSEventLoopGroup.singleton.next(), configuration: configuration)
        connections[identifier] = control
        let transportIdentity = identity
        let result: Result<Void, any Error>
        do {
            try await withTaskCancellationHandler {
                try await Self.run(
                    request: request, configuration: configuration, tlsContext: tlsContext, control: control
                ) { connection in
                    let owners = WebSocketOperationContext.transportIdentities.union([transportIdentity])
                    try await WebSocketOperationContext.$transportIdentities.withValue(owners) {
                        try await operation(connection)
                    }
                }
            } onCancel: {
                control.abort(CancellationError())
            }
            result = .success(())
        } catch {
            result = .failure(await control.normalized(error))
        }
        await control.close()
        connections.removeValue(forKey: identifier)
        if connections.isEmpty {
            let waiters = shutdownWaiters
            shutdownWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
        if Task.isCancelled { throw CancellationError() }
        try result.get()
    }

    public func shutdown() async throws {
        guard !WebSocketOperationContext.transportIdentities.contains(identity) else {
            throw UpstreamWebSocketFailure(kind: .shutdownFromConnection)
        }
        stopped = true
        for control in connections.values { control.abort(UpstreamWebSocketFailure(kind: .transportShutDown)) }
        if !connections.isEmpty {
            await withCheckedContinuation { shutdownWaiters.append($0) }
        }
    }

    private static func run(
        request: UpstreamWebSocketRequest,
        configuration: UpstreamWebSocketConfiguration,
        tlsContext: NIOSSLContext,
        control: WebSocketConnectionControl,
        operation: @escaping @Sendable (UpstreamWebSocketConnection) async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    let outcome = try await WebSocketClientBootstrap.connect(
                        request: request, configuration: configuration, tlsContext: tlsContext, control: control)
                    switch outcome {
                    case .rejected(let response):
                        throw UpstreamWebSocketFailure(kind: .upgradeRejected, response: try await response.get())
                    // swiftlint:disable:next pattern_matching_keywords
                    case .upgraded(let channel, let compression):
                        try await WSCoreConnectionDriver.run(
                            channel: channel,
                            control: control,
                            configuration: configuration,
                            compression: compression,
                            operation: operation)
                    }
                    control.finishSignal()
                } catch {
                    control.abort(error)
                    throw error
                }
            }
            group.addTask { try await control.abortSignal.get() }
            defer {
                group.cancelAll()
                control.finishSignal()
            }
            try await group.next()
        }
    }
}

private enum WebSocketOperationContext {
    @TaskLocal static var transportIdentities: Set<UUID> = []
}
