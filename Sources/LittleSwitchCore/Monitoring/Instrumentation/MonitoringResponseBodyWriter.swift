import HTTPTypes
import Hummingbird
import NIOCore

/// The writer owns its bounded observation state. There is no shared chunk
/// buffer, actor hop for ordinary chunks, or observation of recovered attempts.
package struct MonitoringResponseBodyWriter: ResponseBodyWriter {
    private var writer: any ResponseBodyWriter
    private let context: MonitoringRequestContext
    private var observer = MonitoringResponseFailureObserver()

    package init(writer: any ResponseBodyWriter, context: MonitoringRequestContext) {
        self.writer = writer
        self.context = context
    }

    package mutating func write(_ buffer: ByteBuffer) async throws {
        if observer.append(buffer) { await context.providerResponseFailed() }
        try await writer.write(buffer)
    }

    package consuming func finish(_ trailingHeaders: HTTPFields?) async throws {
        try await writer.finish(trailingHeaders)
    }
}
