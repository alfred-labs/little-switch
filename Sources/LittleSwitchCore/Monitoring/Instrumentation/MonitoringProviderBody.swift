import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import NIOCore

/// Wrap the original provider body before validation or protocol adaptation consumes it.
package struct MonitoringProviderBody: AsyncSequence, Sendable {
    package let body: HTTPClientResponse.Body
    package let context: MonitoringRequestContext
    private let exchangeID = UUID()

    package init(body: HTTPClientResponse.Body, context: MonitoringRequestContext) {
        self.body = body
        self.context = context
    }

    package func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(upstream: body.makeAsyncIterator(), context: context, exchangeID: exchangeID)
    }

    package struct AsyncIterator: AsyncIteratorProtocol {
        var upstream: HTTPClientResponse.Body.AsyncIterator
        let context: MonitoringRequestContext
        let exchangeID: UUID
        private var accumulator = MonitoringUsageAccumulator()
        private var reported: GatewayUsageTotals?
        private var invalidCount = 0
        private var ended = false

        fileprivate init(
            upstream: HTTPClientResponse.Body.AsyncIterator, context: MonitoringRequestContext, exchangeID: UUID
        ) {
            self.upstream = upstream
            self.context = context
            self.exchangeID = exchangeID
        }

        package mutating func next() async throws -> ByteBuffer? {
            guard !ended else { return nil }
            do {
                let buffer = try await upstream.next()
                if let buffer {
                    accumulator.append(Data(buffer.readableBytesView))
                } else {
                    accumulator.finish()
                    ended = true
                }
                await publishChanges()
                return buffer
            } catch {
                accumulator.finish()
                ended = true
                await publishChanges()
                throw error
            }
        }

        private mutating func publishChanges() async {
            if let totals = accumulator.totals, totals != reported {
                reported = totals
                await context.usage(exchangeID: exchangeID, totals: totals)
            }
            if accumulator.invalidSampleCount > invalidCount {
                let delta = accumulator.invalidSampleCount - invalidCount
                invalidCount = accumulator.invalidSampleCount
                await context.invalidUsage(count: delta)
            }
        }
    }
}
