import Foundation

/// Changes complete event data while preserving comments, IDs, retry fields,
/// separators, and byte-identical frames whose payload needs no conversion.
package enum ServerSentEventDataRewriter {
    package enum Error: Swift.Error, Equatable {
        case missingSource
        case invalidData
    }

    private struct Source {
        let original: Data
        let range: Range<Data.Index>
        let separator: Data
    }

    /// Synthetic frames have no source record. Consumers preserving transport
    /// bytes must use the content and absolute range supplied by the decoder.
    package static func originalSource(of frame: ServerSentEventFrame) throws -> (data: Data, range: Range<Int>) {
        guard let data = frame.sourceData, let range = frame.sourceRange else { throw Error.missingSource }
        return (data, range)
    }

    /// Transformed event data is UTF-8 text with LF line breaks, as returned by
    /// the decoder. A raw CR cannot be represented without changing its value.
    package static func rewrite(
        _ bytes: Data,
        sourceOffset: Int = 0,
        frames: [ServerSentEventFrame],
        transform: (Data) throws -> Data
    ) throws -> Data {
        var result = Data()
        var position = 0
        for frame in frames where !frame.terminal {
            let transformed = try transform(frame.data)
            guard transformed != frame.data else { continue }
            guard String(data: transformed, encoding: .utf8) != nil, !transformed.contains(0x0D) else {
                throw Error.invalidData
            }
            let source = try source(
                for: frame, in: bytes, sourceOffset: sourceOffset, after: position)
            result.append(bytes[(bytes.startIndex + position)..<source.range.lowerBound])
            result.append(try replaceDataLines(in: source.original, separator: source.separator, with: transformed))
            result.append(source.separator)
            position = source.range.upperBound - bytes.startIndex
        }
        result.append(bytes[(bytes.startIndex + position)..<bytes.endIndex])
        return result
    }

    private static func source(
        for frame: ServerSentEventFrame, in bytes: Data, sourceOffset: Int, after position: Int
    ) throws -> Source {
        let (original, absolute) = try originalSource(of: frame)
        guard sourceOffset >= 0,
            absolute.lowerBound >= sourceOffset, absolute.upperBound - sourceOffset <= bytes.count
        else { throw Error.missingSource }
        let lower = absolute.lowerBound - sourceOffset
        let upper = absolute.upperBound - sourceOffset
        guard lower >= position, original.count <= upper - lower else { throw Error.missingSource }
        let range = (bytes.startIndex + lower)..<(bytes.startIndex + upper)
        guard bytes[range].starts(with: original) else { throw Error.missingSource }
        let separator = Data(bytes[(range.lowerBound + original.count)..<range.upperBound])
        guard separators.contains(separator) else { throw Error.missingSource }
        return Source(original: original, range: range, separator: separator)
    }

    private static let separators = ["\n\n", "\r\r", "\n\r", "\r\n\r", "\r\r\n", "\n\r\n", "\r\n\n", "\r\n\r\n"]
        .map { Data($0.utf8) }

    private static func replaceDataLines(in original: Data, separator: Data, with transformed: Data) throws -> Data {
        var result = Data()
        var inserted = false
        var position = original.startIndex
        while position < original.endIndex {
            let contentEnd = original[position...].firstIndex { $0 == 0x0A || $0 == 0x0D } ?? original.endIndex
            var lineEnd = contentEnd
            if lineEnd < original.endIndex {
                lineEnd += 1
                if original[contentEnd] == 0x0D, lineEnd < original.endIndex, original[lineEnd] == 0x0A { lineEnd += 1 }
            }
            let content = original[position..<contentEnd]
            if content.elementsEqual("data".utf8) || content.starts(with: "data:".utf8) {
                if !inserted {
                    let ending = original[contentEnd..<lineEnd]
                    let joining =
                        ending.isEmpty ? separator.prefix(separator.starts(with: [0x0D, 0x0A]) ? 2 : 1) : ending
                    let lines = transformed.split(separator: 0x0A, omittingEmptySubsequences: false)
                    for (index, line) in lines.enumerated() {
                        if index > 0 { result.append(joining) }
                        result.append(contentsOf: "data: ".utf8)
                        result.append(line)
                    }
                    result.append(ending)
                    inserted = true
                }
            } else {
                result.append(original[position..<lineEnd])
            }
            position = lineEnd
        }
        guard inserted else { throw Error.missingSource }
        return result
    }
}
