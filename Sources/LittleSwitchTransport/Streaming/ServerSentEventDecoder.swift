import Foundation
import NIOCore

package struct ServerSentEventFrame: Equatable, Sendable {
    package let event: String?
    package let data: Data
    package let terminal: Bool

    package init(event: String?, data: Data, terminal: Bool) {
        self.event = event
        self.data = data
        self.terminal = terminal
    }
}

package struct ServerSentEventDecoder: Sendable {
    package enum Error: Swift.Error, Equatable {
        case frameTooLarge
        case invalidUTF8
        case incompleteFrame
    }

    private var pending = Data()
    private let maximumFrameBytes: Int
    package private(set) var consumedBytes = 0

    package init(maximumFrameBytes: Int) {
        self.maximumFrameBytes = maximumFrameBytes
    }

    package mutating func append(_ buffer: ByteBuffer) throws -> [ServerSentEventFrame] {
        var frames: [ServerSentEventFrame] = []
        // The incoming bytes land directly in the accumulated buffer: it is
        // uniquely referenced here, so the append costs the chunk, not the
        // frame-so-far. A mid-stream `var work = pending` copy would make a
        // large frame delivered in TLS-sized records quadratic.
        let scanStart = pending.count
        pending.append(contentsOf: buffer.readableBytesView)
        let scan = SeparatorScan(work: pending)

        var frameStart = 0
        // A deferred separator carried over from the previous append is
        // accepted or refuted by the first new byte: any byte except LF
        // closes the blank line, exactly as a byte-at-a-time scan would.
        let carried: Int? =
            scanStart > 0 && scanStart < pending.count
            ? scan.deferredSuffixLength(endingAt: scanStart - 1, floor: 0)
            : nil
        if let carried, scan.byte(at: scanStart) != 0x0A {
            if let frame = try scan.consumeFrame(
                endingAt: scanStart - 1,
                separatorLength: carried,
                floor: 0,
                maximumFrameBytes: maximumFrameBytes
            ) {
                frames.append(frame)
            }
            frameStart = scanStart
        }

        let (scanned, finalFrameStart) = try scan.frames(
            from: scanStart,
            frameStart: frameStart,
            maximumFrameBytes: maximumFrameBytes
        )
        frames.append(contentsOf: scanned)

        if finalFrameStart == 0 {
            // Nothing was consumed: the buffer stays pending untouched,
            // without re-copying a still-accumulating frame.
        } else if finalFrameStart == pending.count {
            pending.removeAll(keepingCapacity: true)
        } else {
            pending = scan.suffix(from: finalFrameStart)
        }
        if pending.count - possibleSeparatorPrefixLength > maximumFrameBytes {
            throw Error.frameTooLarge
        }
        consumedBytes += finalFrameStart
        return frames
    }

    package mutating func finish() throws -> [ServerSentEventFrame] {
        guard !pending.isEmpty else {
            return []
        }

        if let separatorLength = deferredSeparatorLength {
            let finishingBytes = pending.count
            let frameData = Data(pending.dropLast(separatorLength))
            pending.removeAll(keepingCapacity: true)
            let frame = try Self.decode(frameData)
            consumedBytes += finishingBytes
            return frame.map { [$0] } ?? []
        }

        guard let residual = String(data: pending, encoding: .utf8) else {
            throw Error.invalidUTF8
        }
        guard residual.allSatisfy(\.isWhitespace) else {
            throw Error.incompleteFrame
        }

        consumedBytes += pending.count
        pending.removeAll(keepingCapacity: true)
        return []
    }

    private var deferredSeparatorLength: Int? {
        if pending.suffix(3).elementsEqual([0x0D, 0x0A, 0x0D]) {
            return 3
        }
        let hasTwoByteSeparator =
            pending.suffix(2).elementsEqual([0x0D, 0x0D])
            || pending.suffix(2).elementsEqual([0x0A, 0x0D])
        if hasTwoByteSeparator {
            return 2
        }
        return nil
    }

    private var possibleSeparatorPrefixLength: Int {
        // The deferred patterns are a prefix of this test's cases (every
        // deferred separator ends in CR and the extras end in LF), so the
        // deferred check runs once here instead of being re-listed by hand.
        if let deferred = deferredSeparatorLength {
            return deferred
        }
        if pending.suffix(2).elementsEqual([0x0D, 0x0A]) {
            return 2
        }
        if pending.last == 0x0D || pending.last == 0x0A {
            return 1
        }
        return 0
    }

    fileprivate static func decode(_ frameData: Data) throws -> ServerSentEventFrame? {
        guard let frame = String(data: frameData, encoding: .utf8) else {
            throw Error.invalidUTF8
        }

        var event: String?
        var dataValues: [String] = []
        let normalized =
            frame
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.first == ":" {
                continue
            }

            let field: Substring
            var value: Substring
            if let colon = line.firstIndex(of: ":") {
                field = line[..<colon]
                value = line[line.index(after: colon)...]
                if value.first == " " {
                    value = value.dropFirst()
                }
            } else {
                field = line
                value = line[line.endIndex...]
            }

            switch field {
            case "event":
                event = String(value)
            case "data":
                dataValues.append(String(value))
            default:
                continue
            }
        }

        guard !dataValues.isEmpty else {
            return nil
        }
        let data = dataValues.joined(separator: "\n")
        if data == "[DONE]" {
            return ServerSentEventFrame(event: event, data: Data(), terminal: true)
        }
        return ServerSentEventFrame(
            event: event,
            data: Data(data.utf8),
            terminal: false
        )
    }
}

private func framesAppend(
    _ frames: inout [ServerSentEventFrame],
    _ frame: ServerSentEventFrame?
) {
    if let frame {
        frames.append(frame)
    }
}

/// Byte-wise separator scan over one concatenated work buffer. Completed
/// separators always end in LF and deferred ones in CR, so the branch logic
/// only engages on those bytes — but the payload walk itself visits every
/// byte through the bounds-checked subscript (a memchr-style pass over the
/// readable view would be the faster shape if this loop ever shows up in a
/// profile).
private struct SeparatorScan {
    let work: Data

    func byte(at position: Int) -> UInt8? {
        guard position >= 0, position < work.count else {
            return nil
        }
        return work[work.startIndex + position]
    }

    /// True when the bytes ending at `position` equal `pattern` without
    /// reaching before `floor`, mirroring a suffix test on the pending
    /// frame alone.
    private func matches(
        _ pattern: [UInt8],
        endingAt position: Int,
        floor: Int
    ) -> Bool {
        let first = position - pattern.count + 1
        guard first >= floor else {
            return false
        }
        for (offset, value) in pattern.enumerated()
        where byte(at: first + offset) != value {
            return false
        }
        return true
    }

    func completedSuffixLength(endingAt position: Int, floor: Int) -> Int? {
        if matches([0x0D, 0x0A, 0x0D, 0x0A], endingAt: position, floor: floor) {
            return 4
        }
        let hasThreeByteSeparator =
            matches([0x0D, 0x0D, 0x0A], endingAt: position, floor: floor)
            || matches([0x0A, 0x0D, 0x0A], endingAt: position, floor: floor)
            || matches([0x0D, 0x0A, 0x0A], endingAt: position, floor: floor)
        if hasThreeByteSeparator {
            return 3
        }
        if matches([0x0A, 0x0A], endingAt: position, floor: floor) {
            return 2
        }
        return nil
    }

    func deferredSuffixLength(endingAt position: Int, floor: Int) -> Int? {
        if matches([0x0D, 0x0A, 0x0D], endingAt: position, floor: floor) {
            return 3
        }
        let hasTwoByteSeparator =
            matches([0x0D, 0x0D], endingAt: position, floor: floor)
            || matches([0x0A, 0x0D], endingAt: position, floor: floor)
        if hasTwoByteSeparator {
            return 2
        }
        return nil
    }

    func consumeFrame(
        endingAt position: Int,
        separatorLength: Int,
        floor: Int,
        maximumFrameBytes: Int
    ) throws -> ServerSentEventFrame? {
        let cut = position + 1 - separatorLength
        guard cut - floor <= maximumFrameBytes else {
            throw ServerSentEventDecoder.Error.frameTooLarge
        }
        return try ServerSentEventDecoder.decode(
            work.subdata(in: (work.startIndex + floor)..<(work.startIndex + cut))
        )
    }

    func frames(
        from scanStart: Int,
        frameStart: Int,
        maximumFrameBytes: Int
    ) throws -> ([ServerSentEventFrame], Int) {
        var frames: [ServerSentEventFrame] = []
        var frameStart = frameStart
        var position = scanStart
        while position < work.count {
            var next = position
            while let value = byte(at: next), value != 0x0A, value != 0x0D {
                next += 1
            }
            guard let separatorByte = byte(at: next) else {
                break
            }
            let completedLength =
                separatorByte == 0x0A
                ? completedSuffixLength(endingAt: next, floor: frameStart)
                : nil
            let deferredLength =
                separatorByte == 0x0D
                ? deferredSuffixLength(endingAt: next, floor: frameStart)
                : nil
            let following = byte(at: next + 1)
            if let length = completedLength {
                framesAppend(
                    &frames,
                    try consumeFrame(
                        endingAt: next,
                        separatorLength: length,
                        floor: frameStart,
                        maximumFrameBytes: maximumFrameBytes
                    )
                )
                frameStart = next + 1
            } else if let length = deferredLength, let following, following != 0x0A {
                framesAppend(
                    &frames,
                    try consumeFrame(
                        endingAt: next,
                        separatorLength: length,
                        floor: frameStart,
                        maximumFrameBytes: maximumFrameBytes
                    )
                )
                frameStart = next + 1
            }
            position = next + 1
        }
        return (frames, frameStart)
    }

    func suffix(from frameStart: Int) -> Data {
        work.subdata(in: (work.startIndex + frameStart)..<work.endIndex)
    }
}
