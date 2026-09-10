import Foundation
import HTTPTypes
import Hummingbird
import NIOCore

private final class ResponseBodyDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ buffer: ByteBuffer) {
        lock.withLock {
            storage.append(contentsOf: buffer.readableBytesView)
        }
    }

    var data: Data {
        lock.withLock { storage }
    }
}

private struct ResponseBodyDataWriter: ResponseBodyWriter {
    let box: ResponseBodyDataBox

    mutating func write(_ buffer: ByteBuffer) async throws {
        box.append(buffer)
    }

    consuming func finish(_ trailingHeaders: HTTPFields?) async throws {
        _ = trailingHeaders
    }
}

func responseBodyData(_ body: ResponseBody) async throws -> Data {
    let box = ResponseBodyDataBox()
    try await body.write(ResponseBodyDataWriter(box: box))
    return box.data
}
