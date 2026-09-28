import NIOCore
import NIOSSL

/// A physical deadline independent of session scheduling or writable buffers.
/// Keep it armed through the WebSocket and TLS closing handshakes.
package enum GatewayWebSocketDeadline {
    @discardableResult
    package static func install(
        on channel: any Channel, lifetime: TimeAmount, closeGrace: TimeAmount
    ) -> EventLoopFuture<Void> {
        let deadline = channel.eventLoop.scheduleTask(in: lifetime + closeGrace) {
            if let tls = try? channel.pipeline.syncOperations.context(handlerType: NIOSSLServerHandler.self) {
                // Closing before TLS bypasses its own close-notify grace. The
                // application has already spent its complete closing budget.
                tls.close(promise: nil)
            } else {
                channel.close(promise: nil)
            }
        }
        channel.closeFuture.whenComplete { _ in deadline.cancel() }
        return deadline.futureResult
    }
}
