import CCompressZlib
import NIOCore
import NIOWebSocket

/// One physical connection owns one inflater. Message budgets are logical bytes;
/// BFINAL restarts block parsing, not the negotiated sliding-window history.
actor WebSocketInflater {
    private enum MessageState { case idle, plain, compressed }
    private let stream: RawDeflateStream
    private let maximumBytes: Int
    private let noContextTakeover: Bool
    private var state = MessageState.idle
    private var decodedBytes = 0

    init(maximumBytes: Int, windowBits: Int, noContextTakeover: Bool) throws {
        guard maximumBytes > 0, maximumBytes <= Int(UInt32.max) else {
            throw UpstreamWebSocketFailure(kind: .invalidConfiguration)
        }
        self.stream = try RawDeflateStream(windowBits: windowBits)
        self.maximumBytes = maximumBytes
        self.noContextTakeover = noContextTakeover
    }

    func process(_ frame: WebSocketFrame) throws -> WebSocketFrame {
        guard frame.opcode == .text || frame.opcode == .binary || frame.opcode == .continuation else { return frame }
        if frame.opcode == .continuation {
            guard state != .idle else { throw UpstreamWebSocketFailure(kind: .protocolViolation) }
        } else {
            guard state == .idle else { throw UpstreamWebSocketFailure(kind: .protocolViolation) }
            state = frame.rsv1 ? .compressed : .plain
            decodedBytes = 0
        }
        guard state == .compressed else {
            if frame.fin { state = .idle }
            return frame
        }

        var input = frame.unmaskedData
        var output = try stream.decode(&input, maximumBytes: maximumBytes - decodedBytes)
        decodedBytes += output.readableBytes
        if frame.fin {
            // RFC 7692 strips the length bytes of an empty stored block. Check
            // its header before restoring the trailer: EOF alone also accepts
            // truncated streams that happened not to produce a zlib error.
            guard stream.atSyncPoint else { throw UpstreamWebSocketFailure(kind: .protocolViolation) }
            var trailer = ByteBuffer(bytes: [0x00, 0x00, 0xff, 0xff])
            let tail = try stream.decode(&trailer, maximumBytes: maximumBytes - decodedBytes)
            output.writeImmutableBuffer(tail)
            if noContextTakeover { stream.reset(keepingWindow: false) }
            state = .idle
        }
        var result = frame
        result.data = output
        result.rsv1 = false
        return result
    }
}

/// Non-Sendable C state never leaves the owning actor. Its stable allocation is
/// required by zlib; pointers into ByteBuffers are borrowed for one step only.
private final class RawDeflateStream {
    private struct Step {
        let status: Int32
        let consumed: Int
        let output: ByteBuffer
    }

    private let stream: UnsafeMutablePointer<z_stream>

    init(windowBits: Int) throws {
        guard (8...15).contains(windowBits) else {
            throw UpstreamWebSocketFailure(kind: .invalidConfiguration)
        }
        let allocation = UnsafeMutablePointer<z_stream>.allocate(capacity: 1)
        allocation.initialize(to: z_stream())
        guard CCompressZlib_inflateInit2(allocation, -Int32(windowBits)) == Z_OK else {
            _ = inflateEnd(allocation)
            allocation.deinitialize(count: 1)
            allocation.deallocate()
            throw UpstreamWebSocketFailure(kind: .invalidConfiguration)
        }
        stream = allocation
    }

    deinit {
        _ = inflateEnd(stream)
        stream.deinitialize(count: 1)
        stream.deallocate()
    }

    var atSyncPoint: Bool { inflateSyncPoint(stream) == 1 }

    func reset(keepingWindow: Bool) {
        // Both reset operations only reject an invalid internal z_stream.
        let result = keepingWindow ? inflateResetKeep(stream) : inflateReset(stream)
        precondition(result == Z_OK, "Invalid inflater state")
    }

    func decode(_ input: inout ByteBuffer, maximumBytes: Int) throws -> ByteBuffer {
        var output = ByteBuffer()
        while true {
            // One sentinel byte distinguishes an exact boundary from excess
            // output without allocating beyond the remaining logical budget.
            let capacity = min(16 * 1_024, maximumBytes - output.readableBytes + 1)
            let step = inflateStep(&input, capacity: capacity)
            guard step.output.readableBytes <= maximumBytes - output.readableBytes else {
                throw UpstreamWebSocketFailure(kind: .messageTooLarge)
            }
            output.writeImmutableBuffer(step.output)
            switch step.status {
            case Z_STREAM_END: reset(keepingWindow: true)
            case Z_OK, Z_BUF_ERROR: break
            default: throw UpstreamWebSocketFailure(kind: .protocolViolation)
            }
            if input.readableBytes == 0, step.output.readableBytes < capacity { return output }
            guard step.consumed > 0 || step.output.readableBytes > 0 else {
                throw UpstreamWebSocketFailure(kind: .protocolViolation)
            }
        }
    }

    private func inflateStep(_ input: inout ByteBuffer, capacity: Int) -> Step {
        var output = ByteBufferAllocator().buffer(capacity: capacity)
        var consumed = 0
        var status = Z_OK
        _ = input.withUnsafeReadableBytes { source in
            output.writeWithUnsafeMutableBytes(minimumWritableBytes: capacity) { destination in
                let count = min(source.count, Int(UInt32.max))
                stream.pointee.next_in = source.baseAddress.map {
                    UnsafeMutablePointer(mutating: $0.assumingMemoryBound(to: UInt8.self))
                }
                stream.pointee.avail_in = UInt32(count)
                stream.pointee.next_out = destination.baseAddress?.assumingMemoryBound(to: UInt8.self)
                stream.pointee.avail_out = UInt32(capacity)
                status = CCompressZlib.inflate(stream, Z_NO_FLUSH)
                consumed = count - Int(stream.pointee.avail_in)
                let produced = capacity - Int(stream.pointee.avail_out)
                stream.pointee.next_in = nil
                stream.pointee.next_out = nil
                return produced
            }
        }
        input.moveReaderIndex(forwardBy: consumed)
        return Step(status: status, consumed: consumed, output: output)
    }
}
