import CoreFoundation
import Foundation

private struct AnthropicMessageStartPatch: Sendable {
    let before: Data
    let originalFrame: Data
    var after: Data
    let inputTokenRange: Range<Int>

    var originalOutput: [Data] {
        [before, originalFrame, after].filter { !$0.isEmpty }
    }
}

private enum AnthropicInitialUsageNormalizerState: Sendable {
    case classifying(prefix: Data, frameStart: Int, searchOffset: Int)
    case waitingForEstimate(AnthropicMessageStartPatch)
    case passthrough
}

private enum AnthropicInitialUsageParsedFrame {
    case ignorable
    case messageStart(inputTokens: Int, inputTokenRange: Range<Int>)
    case invalid
}

private struct AnthropicInitialUsageSSEFields {
    let event: String?
    let payload: Data
    let rawOffsets: [Int?]
}

private struct AnthropicInitialUsageRawFrameBoundary {
    let range: Range<Int>
    let separatorByteCount: Int
}

private func integralTokenCount(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber,
        CFGetTypeID(number) == CFNumberGetTypeID()
    else {
        return nil
    }
    let count = number.intValue
    guard number.compare(NSNumber(value: count)) == .orderedSame else {
        return nil
    }
    return count
}

private func rewrittenFrame(
    originalFrame: Data,
    inputTokenRange: Range<Int>,
    inputTokens: Int
) -> Data {
    precondition(inputTokenRange.lowerBound >= originalFrame.startIndex)
    precondition(inputTokenRange.upperBound <= originalFrame.endIndex)
    var frame = originalFrame
    frame.replaceSubrange(inputTokenRange, with: Data(String(inputTokens).utf8))
    return frame
}

package struct AnthropicInitialUsageNormalizer: Sendable {
    package enum Decision: Equatable, Sendable {
        case buffering
        case native(inputTokens: Int, output: [Data])
        case estimateRequired
        case output([Data])
    }

    private let maximumPrefixBytes: Int
    private var state: AnthropicInitialUsageNormalizerState = .classifying(
        prefix: Data(),
        frameStart: 0,
        searchOffset: 0
    )

    package init(maximumPrefixBytes: Int = 64 * 1_024) {
        self.maximumPrefixBytes = max(0, maximumPrefixBytes)
    }

    package mutating func append(_ bytes: Data) -> Decision {
        switch state {
        case .passthrough:
            return .output(bytes.isEmpty ? [] : [bytes])
        case .waitingForEstimate(var patch):
            patch.after.append(bytes)
            state = .waitingForEstimate(patch)
            return .estimateRequired
        case .classifying(var prefix, let frameStart, let searchOffset):
            prefix.append(bytes)
            return classify(
                prefix,
                frameStart: frameStart,
                searchOffset: searchOffset
            )
        }
    }

    package mutating func resolve(
        _ resolution: AnthropicInitialUsageResolution
    ) -> [Data] {
        guard case .waitingForEstimate(let patch) = state else {
            return []
        }
        state = .passthrough

        let inputTokens: Int
        switch resolution {
        case .native(let value), .providerEstimate(let value, _),
            .localEstimate(let value, _, _):
            inputTokens = value
        }
        guard inputTokens >= 0 else {
            return patch.originalOutput
        }
        let rewrittenFrame = rewrittenFrame(
            originalFrame: patch.originalFrame,
            inputTokenRange: patch.inputTokenRange,
            inputTokens: inputTokens
        )

        return [patch.before, rewrittenFrame, patch.after].filter { !$0.isEmpty }
    }

    package mutating func finish() -> [Data] {
        switch state {
        case .passthrough:
            return []
        case .classifying(let prefix, _, _):
            state = .passthrough
            return prefix.isEmpty ? [] : [prefix]
        case .waitingForEstimate(let patch):
            state = .passthrough
            return patch.originalOutput
        }
    }

    private mutating func classify(
        _ prefix: Data,
        frameStart initialFrameStart: Int,
        searchOffset initialSearchOffset: Int
    ) -> Decision {
        var frameStart = initialFrameStart
        var searchOffset = initialSearchOffset
        while let boundary = nextBoundary(
            in: prefix,
            frameStart: frameStart,
            searchFrom: searchOffset
        ) {
            let rawFrame = Data(prefix[boundary.range])
            guard boundary.range.upperBound <= maximumPrefixBytes else {
                state = .passthrough
                return .output([prefix])
            }
            let contentEnd = rawFrame.count - boundary.separatorByteCount
            let frameContent = Data(rawFrame.prefix(contentEnd))

            switch parse(frameContent) {
            case .ignorable:
                frameStart = boundary.range.upperBound
                searchOffset = frameStart
            case .invalid:
                state = .passthrough
                return .output([prefix])
            // swiftlint:disable:next pattern_matching_keywords
            case .messageStart(let inputTokens, let inputTokenRange):
                if inputTokens > 0 {
                    state = .passthrough
                    return .native(
                        inputTokens: inputTokens,
                        output: [prefix]
                    )
                }

                let patch = AnthropicMessageStartPatch(
                    before: Data(prefix[..<boundary.range.lowerBound]),
                    originalFrame: rawFrame,
                    after: Data(prefix[boundary.range.upperBound...]),
                    inputTokenRange: inputTokenRange
                )
                state = .waitingForEstimate(patch)
                return .estimateRequired
            }
        }

        if prefix.count > maximumPrefixBytes {
            state = .passthrough
            return .output([prefix])
        }
        state = .classifying(
            prefix: prefix,
            frameStart: frameStart,
            searchOffset: max(frameStart, prefix.count - 3)
        )
        return .buffering
    }

    private func nextBoundary(
        in data: Data,
        frameStart: Int,
        searchFrom: Int
    ) -> AnthropicInitialUsageRawFrameBoundary? {
        guard searchFrom < data.count else { return nil }
        let searchRange = searchFrom..<data.count
        let lf = data.range(of: Data([0x0A, 0x0A]), options: [], in: searchRange)
        let crlf = data.range(
            of: Data([0x0D, 0x0A, 0x0D, 0x0A]),
            options: [],
            in: searchRange
        )

        switch (lf, crlf) {
        case (nil, nil):
            return nil
        case (.some(let range), nil):
            return AnthropicInitialUsageRawFrameBoundary(
                range: frameStart..<range.upperBound,
                separatorByteCount: 2
            )
        case (nil, .some(let range)):
            return AnthropicInitialUsageRawFrameBoundary(
                range: frameStart..<range.upperBound,
                separatorByteCount: 4
            )
        // swiftlint:disable:next pattern_matching_keywords
        case (.some(let lfRange), .some(let crlfRange)):
            if lfRange.lowerBound < crlfRange.lowerBound {
                return AnthropicInitialUsageRawFrameBoundary(
                    range: frameStart..<lfRange.upperBound,
                    separatorByteCount: 2
                )
            }
            return AnthropicInitialUsageRawFrameBoundary(
                range: frameStart..<crlfRange.upperBound,
                separatorByteCount: 4
            )
        }
    }

    private func parse(_ frame: Data) -> AnthropicInitialUsageParsedFrame {
        guard let fields = sseFields(frame) else {
            return .invalid
        }
        guard !fields.payload.isEmpty else {
            return fields.event == nil ? .ignorable : .invalid
        }
        guard fields.payload != Data("[DONE]".utf8),
            let root = try? JSONSerialization.jsonObject(with: fields.payload) as? [String: Any],
            let type = root["type"] as? String
        else {
            return .invalid
        }
        if fields.event == "ping", type == "ping" {
            return .ignorable
        }
        guard fields.event == "message_start", type == "message_start",
            let message = root["message"] as? [String: Any],
            let usage = message["usage"] as? [String: Any],
            let inputTokens = integralTokenCount(usage["input_tokens"]),
            inputTokens >= 0,
            let inputTokenRange = inputTokenRange(
                in: fields.payload,
                rawOffsets: fields.rawOffsets
            )
        else {
            return .invalid
        }
        return .messageStart(
            inputTokens: inputTokens,
            inputTokenRange: inputTokenRange
        )
    }

    private func sseFields(_ frame: Data) -> AnthropicInitialUsageSSEFields? {
        let bytes = Array(frame)
        var event: String?
        var payload = Data()
        var rawOffsets: [Int?] = []
        var hasData = false
        var cursor = 0

        while cursor < bytes.count {
            let lineStart = cursor
            while cursor < bytes.count, bytes[cursor] != 0x0A, bytes[cursor] != 0x0D {
                cursor += 1
            }
            let lineEnd = cursor
            if cursor < bytes.count {
                let hasCRLF =
                    bytes[cursor] == 0x0D
                    && cursor + 1 < bytes.count
                    && bytes[cursor + 1] == 0x0A
                if hasCRLF {
                    cursor += 2
                } else {
                    cursor += 1
                }
            }

            guard lineStart < lineEnd, bytes[lineStart] != 0x3A else {
                continue
            }
            let colon = (lineStart..<lineEnd).first { bytes[$0] == 0x3A }
            let fieldEnd = colon ?? lineEnd
            var valueStart = colon.map { $0 + 1 } ?? lineEnd
            if valueStart < lineEnd, bytes[valueStart] == 0x20 {
                valueStart += 1
            }
            guard
                let field = String(
                    bytes: bytes[lineStart..<fieldEnd],
                    encoding: .utf8
                )
            else {
                return nil
            }

            switch field {
            case "event":
                guard
                    let value = String(
                        bytes: bytes[valueStart..<lineEnd],
                        encoding: .utf8
                    )
                else {
                    return nil
                }
                event = value
            case "data":
                if hasData {
                    payload.append(0x0A)
                    rawOffsets.append(nil)
                }
                payload.append(contentsOf: bytes[valueStart..<lineEnd])
                rawOffsets.append(contentsOf: (valueStart..<lineEnd).map(Optional.some))
                hasData = true
            default:
                continue
            }
        }
        return AnthropicInitialUsageSSEFields(
            event: event,
            payload: payload,
            rawOffsets: rawOffsets
        )
    }

    private func inputTokenRange(
        in payload: Data,
        rawOffsets: [Int?]
    ) -> Range<Int>? {
        var scanner = AnthropicJSONSourceScanner(data: payload)
        let ranges = scanner.inputTokenRanges()
        guard ranges.count == 1, let payloadRange = ranges.first else {
            return nil
        }
        precondition(payloadRange.upperBound <= rawOffsets.count)
        let mappedOffsets = rawOffsets[payloadRange].compactMap(\.self)
        precondition(mappedOffsets.count == payloadRange.count)
        let rawLowerBound = mappedOffsets[0]
        let rawLastIndex = mappedOffsets[mappedOffsets.count - 1]
        let rawRange = rawLowerBound..<(rawLastIndex + 1)
        precondition(rawRange.count == payloadRange.count)
        return rawRange
    }

}
