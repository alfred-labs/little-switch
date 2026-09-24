import Foundation
import Testing

@testable import LittleSwitchCore

struct ChatGPTStreamChannelTests {
    @Test func cancellingTheConsumerTaskClosesTheChannel() async throws {
        let channel = ChatGPTStreamChannel()
        let waiting = AsyncTestGate()
        let consumers = (0..<2).map { _ in
            Task {
                do {
                    _ = try await channel.next()
                    return ChatGPTStreamChannel.Failure?.none
                } catch let error as ChatGPTStreamChannel.Failure {
                    if error == .concurrentAccess { await waiting.open() }
                    return error
                } catch {
                    Issue.record(error)
                    return nil
                }
            }
        }
        try await waiting.wait(description: "one consumer suspended and the other refused")
        for consumer in consumers { consumer.cancel() }
        let failures = await [consumers[0].value, consumers[1].value]
        #expect(failures.contains(.cancelled))
        #expect(failures.contains(.concurrentAccess))
        await #expect(throws: ChatGPTStreamChannel.Failure.cancelled) { try await channel.send(Data("late".utf8)) }
    }
    @Test func preservesChunkOrderAndEndsAfterTheProducerFinishes() async throws {
        let channel = ChatGPTStreamChannel()
        let expected = [Data("first".utf8), Data("second".utf8)]
        let producer = Task {
            for data in expected { try await channel.send(data) }
            await channel.finish()
        }
        do {
            var received: [Data] = []
            while let data = try await channel.next() { received.append(data) }
            try await producer.value
            #expect(received == expected)
            #expect(try await channel.next() == nil)
        } catch {
            await channel.cancel()
            _ = try? await producer.value
            throw error
        }
    }

    @Test func cancellationReleasesBothSidesAndRejectsSubsequentSends() async {
        let sending = ChatGPTStreamChannel()
        let producer = Task { try await sending.send(Data("pending".utf8)) }
        await sending.cancel()
        await #expect(throws: ChatGPTStreamChannel.Failure.cancelled) { try await producer.value }
        await #expect(throws: ChatGPTStreamChannel.Failure.cancelled) { try await sending.send(Data()) }

        let receiving = ChatGPTStreamChannel()
        let consumer = Task { try await receiving.next() }
        await receiving.cancel()
        await #expect(throws: ChatGPTStreamChannel.Failure.cancelled) { try await consumer.value }
    }

    @Test func finishingAnEmptyStreamIsIdempotent() async throws {
        let channel = ChatGPTStreamChannel()
        await channel.finish()
        await channel.finish()
        #expect(try await channel.next() == nil)
    }
}
