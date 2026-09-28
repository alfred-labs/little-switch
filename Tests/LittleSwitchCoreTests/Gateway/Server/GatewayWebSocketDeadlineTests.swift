import NIOCore
import NIOEmbedded
import Testing

@testable import LittleSwitchCore

@Suite("Responses WebSocket connection deadline")
struct GatewayWebSocketDeadlineTests {
    @Test("The physical channel stays open through its grace and closes at the hard deadline")
    func closesAtDeadline() throws {
        let channel = EmbeddedChannel()
        try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 0)).wait()
        defer { _ = try? channel.finish() }
        GatewayWebSocketDeadline.install(on: channel, lifetime: .seconds(2), closeGrace: .seconds(1))

        channel.embeddedEventLoop.advanceTime(by: .seconds(2))
        #expect(channel.isActive)
        channel.embeddedEventLoop.advanceTime(by: .milliseconds(999))
        #expect(channel.isActive)
        channel.embeddedEventLoop.advanceTime(by: .milliseconds(1))
        #expect(!channel.isActive)
    }

    @Test("A closed connection cancels its deadline before it can run")
    func closeCancelsDeadline() throws {
        let channel = EmbeddedChannel()
        try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 0)).wait()
        defer { _ = try? channel.finish() }
        let deadline = GatewayWebSocketDeadline.install(
            on: channel, lifetime: .seconds(2), closeGrace: .seconds(1))
        try channel.close().wait()
        channel.embeddedEventLoop.advanceTime(by: .seconds(4))

        do {
            try deadline.wait()
            Issue.record("The deadline should have been cancelled when the channel closed")
        } catch EventLoopError.cancelled {}
        #expect(!channel.isActive)
    }

    @Test("The hard deadline releases an async writer suspended by socket backpressure")
    func closesBlockedWriter() async throws {
        let channel = NIOAsyncTestingChannel()
        let wrapped = try await channel.testingEventLoop.executeInContext {
            try NIOAsyncChannel<Never, ByteBuffer>(wrappingChannelSynchronously: channel)
        }
        try await channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 0)).get()
        try await channel.testingEventLoop.executeInContext {
            channel.isWritable = false
            channel.pipeline.fireChannelWritabilityChanged()
        }
        GatewayWebSocketDeadline.install(on: channel, lifetime: .seconds(2), closeGrace: .seconds(1))
        let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let writer = Task {
            try await wrapped.executeThenClose { _, outbound in
                started.continuation.yield(())
                started.continuation.finish()
                try await outbound.write(ByteBuffer(string: "blocked response"))
            }
        }
        for await _ in started.stream {}
        await channel.testingEventLoop.run()
        #expect(channel.isActive)
        #expect(try await channel.readOutbound(as: ByteBuffer.self) == nil)

        await channel.testingEventLoop.advanceTime(by: .seconds(3))
        #expect(!channel.isActive)
        // Release the fixture even while exercising the pre-fix behavior.
        if channel.isActive { try await channel.close().get() }
        try await channel.closeFuture.get()
        await #expect(throws: (any Error).self) { try await writer.value }
        _ = try await channel.finish(acceptAlreadyClosed: true)
    }
}
