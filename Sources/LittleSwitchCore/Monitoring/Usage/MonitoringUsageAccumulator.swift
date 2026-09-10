import Foundation

/// A bounded lexical reader of provider usage, before client-side rewriting.
/// Only protocol keys and a small usage object are retained; response content
/// is traversed without buffering it. A reader belongs to one HTTP exchange.
package struct MonitoringUsageAccumulator: Sendable {
    private enum Path: Sendable {
        case root, message, response, other
    }

    private struct Container: Sendable {
        var path: Path
        var isObject: Bool
        var expectingKey = true
        var key: String?
    }

    package private(set) var totals: GatewayUsageTotals?
    package private(set) var invalidSampleCount = 0
    private let maximumUsageBytes: Int
    private var containers: [Container] = []
    private var skippedDepth = 0
    private var inString = false
    private var escaped = false
    private var readingKey = false
    private var keyOverflow = false
    private(set) var keyBytes = Data()
    private(set) var sample = Data()
    private var sampleDepth: Int?
    private var sampleDiscarded = false

    package init(maximumUsageBytes: Int = 16 * 1_024) {
        self.maximumUsageBytes = max(1, maximumUsageBytes)
    }

    package mutating func append(_ bytes: Data) {
        for byte in bytes { consume(byte) }
    }

    package mutating func finish() {
        if sampleDepth != nil, !sampleDiscarded { invalidSampleCount += 1 }
        containers.removeAll(keepingCapacity: true)
        skippedDepth = 0
        inString = false
        escaped = false
        readingKey = false
        keyOverflow = false
        keyBytes.removeAll(keepingCapacity: true)
        sample.removeAll(keepingCapacity: true)
        sampleDepth = nil
        sampleDiscarded = false
    }

    private mutating func consume(_ byte: UInt8) {
        if sampleDepth != nil, !sampleDiscarded {
            if sample.count < maximumUsageBytes {
                sample.append(byte)
            } else {
                discardSample()
            }
        }
        if inString {
            consumeString(byte)
            return
        }
        switch byte {
        case 34:
            inString = true
            readingKey =
                skippedDepth == 0 && containers.last?.isObject == true
                && containers.last?.expectingKey == true
            keyOverflow = false
            keyBytes.removeAll(keepingCapacity: true)
            if readingKey { keyBytes.append(byte) }
        case 123, 91:
            openContainer(isObject: byte == 123)
        case 125, 93:
            closeContainer(isObject: byte == 125)
        case 44:
            if skippedDepth == 0, !containers.isEmpty {
                containers[containers.count - 1].expectingKey = true
                containers[containers.count - 1].key = nil
            }
        default:
            break
        }
    }

    private mutating func consumeString(_ byte: UInt8) {
        if readingKey, !keyOverflow {
            if keyBytes.count < 256 {
                keyBytes.append(byte)
            } else {
                keyOverflow = true
                keyBytes.removeAll(keepingCapacity: true)
            }
        }
        if escaped {
            escaped = false
        } else if byte == 92 {
            escaped = true
        } else if byte == 34 {
            inString = false
            if readingKey, !containers.isEmpty {
                let key = keyOverflow ? nil : try? JSONDecoder().decode(String.self, from: keyBytes)
                // Only protocol keys influence paths. Arbitrary user keys are
                // discarded immediately instead of becoming retained metadata.
                containers[containers.count - 1].key =
                    ["usage", "message", "response"].contains(key) ? key : nil
                containers[containers.count - 1].expectingKey = false
            }
            keyBytes.removeAll(keepingCapacity: true)
            readingKey = false
        }
    }

    private mutating func openContainer(isObject: Bool) {
        guard skippedDepth == 0, containers.count < 64 else {
            skippedDepth += 1
            if sampleDepth != nil { discardSample() }
            return
        }
        var path = Path.other
        var capturesUsage = false
        if let parent = containers.last {
            if isObject, parent.isObject {
                capturesUsage =
                    parent.key == "usage"
                    && (parent.path == .root || parent.path == .message || parent.path == .response)
                if parent.path == .root {
                    if parent.key == "message" { path = .message }
                    if parent.key == "response" { path = .response }
                }
            }
            containers[containers.count - 1].key = nil
        } else if isObject {
            path = .root
        }
        containers.append(Container(path: path, isObject: isObject))
        if capturesUsage, sampleDepth == nil {
            sampleDepth = containers.count
            sampleDiscarded = false
            sample = Data([123])
        }
    }

    private mutating func closeContainer(isObject: Bool) {
        if skippedDepth > 0 {
            skippedDepth -= 1
            return
        }
        guard let last = containers.last else { return }
        guard last.isObject == isObject else {
            finish()
            return
        }
        if sampleDepth == containers.count {
            completeSample()
        }
        containers.removeLast()
    }

    private mutating func discardSample() {
        guard !sampleDiscarded else { return }
        sampleDiscarded = true
        invalidSampleCount += 1
        sample.removeAll(keepingCapacity: true)
    }

    private mutating func completeSample() {
        if !sampleDiscarded {
            do {
                if let measurement = try MonitoringUsageMeasurement.decode(sample) {
                    totals = totals?.merging(measurement) ?? measurement
                }
            } catch {
                invalidSampleCount += 1
            }
        }
        sample.removeAll(keepingCapacity: true)
        sampleDepth = nil
        sampleDiscarded = false
    }
}
