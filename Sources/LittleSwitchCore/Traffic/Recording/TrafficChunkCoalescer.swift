import Foundation
import LittleSwitchCommon

package struct TrafficChunkCoalescer: Sendable {
    package static let defaultThreshold = 64 * 1_024

    private let threshold: Int
    private var residual: Data

    package init(threshold: Int = defaultThreshold) {
        precondition(threshold > 0)
        self.threshold = threshold
        residual = Data()
        residual.reserveCapacity(threshold)
    }

    package mutating func append(_ fragment: Data) -> [Data] {
        guard !fragment.isEmpty else {
            return []
        }

        var chunks: [Data] = []
        chunks.reserveCapacity(fragment.count / threshold + 1)
        var index = fragment.startIndex

        while index < fragment.endIndex {
            let appendedCount = min(threshold - residual.count, fragment.endIndex - index)
            let nextIndex = index + appendedCount
            residual.append(contentsOf: fragment[index..<nextIndex])
            index = nextIndex

            if residual.count == threshold {
                chunks.append(residual)
                residual = Data()
                residual.reserveCapacity(threshold)
            }
        }
        return chunks
    }

    package mutating func flush() -> [Data] {
        guard !residual.isEmpty else {
            return []
        }
        let chunk = residual
        residual = Data()
        residual.reserveCapacity(threshold)
        return [chunk]
    }
}

package enum TrafficChunkRecordingTarget: Sendable {
    case upstream(attempt: Int)
    case client
}

package func recordTrafficChunks(
    _ chunks: [Data],
    target: TrafficChunkRecordingTarget,
    recorder: any TrafficRecording,
    eventID: UUID
) {
    for chunk in chunks {
        let action: TrafficAction
        switch target {
        case .upstream(let attempt):
            action = .upstreamResponseChunk(
                TrafficUpstreamResponseChunk(attempt: attempt, bytes: chunk)
            )
        case .client:
            action = .clientResponseChunk(chunk)
        }
        recorder.record(eventID: eventID, action: action)
    }
}
