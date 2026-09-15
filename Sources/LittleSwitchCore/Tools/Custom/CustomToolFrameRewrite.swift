import Foundation
import LittleSwitchTransport
import LittleSwitchWire

enum CustomToolFrameRewrite {
    enum Edit {
        case keep
        case replace(JSONValue)
        case suppress
    }

    /// Only an adapted event's data/type change. Comments, IDs, retry fields,
    /// line endings and ordinary frames are kept from the original source.
    static func apply(_ edit: Edit, frame: ServerSentEventFrame, source: Data, offset: Int) throws -> Data {
        switch edit {
        case .keep: return source
        case .replace(let json):
            let data = try json.serializedData()
            let rewritten = try ServerSentEventDataRewriter.rewrite(
                source,
                sourceOffset: offset,
                frames: [frame]
            ) { _ in data }
            guard let type = json.object?[OpenAIResponsesCompletedEvent.Key.type.rawValue]?.string, frame.event != nil,
                frame.event != type
            else {
                return rewritten
            }
            return lines(rewritten) { line in
                isField(line, "event") ? Data("event: \(type)".utf8) : line
            }
        case .suppress:
            return lines(source) { line in
                isField(line, "data") || isField(line, "event") ? nil : line
            }
        }
    }

    private static func isField(_ line: Data, _ field: String) -> Bool {
        line.elementsEqual(field.utf8) || line.starts(with: (field + ":").utf8)
    }

    private static func lines(_ source: Data, transform: (Data) -> Data?) -> Data {
        var output = Data()
        var index = source.startIndex
        while index < source.endIndex {
            let end = source[index...].firstIndex { $0 == 10 || $0 == 13 } ?? source.endIndex
            var next = end
            if next < source.endIndex {
                next += 1
                if source[end] == 13, next < source.endIndex, source[next] == 10 { next += 1 }
            }
            if let line = transform(Data(source[index..<end])) {
                output.append(line)
                output.append(source[end..<next])
            }
            index = next
        }
        return output
    }
}
