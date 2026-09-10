import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Traffic chunk coalescer")
struct TrafficChunkCoalescerTests {
    @Test("Fragments stay buffered until the threshold and flush exactly")
    func thresholdAndResidualFlush() {
        var coalescer = TrafficChunkCoalescer(threshold: 4)

        #expect(coalescer.append(Data()).isEmpty)
        #expect(coalescer.append(Data([0, 1, 2])).isEmpty)
        #expect(coalescer.append(Data([3, 4])) == [Data([0, 1, 2, 3])])
        #expect(coalescer.flush() == [Data([4])])
        #expect(coalescer.flush().isEmpty)
    }

    @Test("An exact threshold emits without a residual")
    func exactThreshold() {
        var coalescer = TrafficChunkCoalescer(threshold: 4)

        #expect(coalescer.append(Data([0, 1, 2, 3])) == [Data([0, 1, 2, 3])])
        #expect(coalescer.flush().isEmpty)
    }

    @Test("Large fragments emit every complete threshold chunk in order")
    func fragmentLargerThanThreshold() {
        var coalescer = TrafficChunkCoalescer(threshold: 4)
        let fragment = Data(0...10)

        #expect(
            coalescer.append(fragment) == [
                Data([0, 1, 2, 3]),
                Data([4, 5, 6, 7]),
            ]
        )
        #expect(coalescer.flush() == [Data([8, 9, 10])])
    }

    @Test("Copies retain independent residual buffers")
    func valueSemantics() {
        var original = TrafficChunkCoalescer(threshold: 4)
        #expect(original.append(Data([0, 1])).isEmpty)
        var copy = original

        #expect(original.append(Data([2, 3])) == [Data([0, 1, 2, 3])])
        #expect(copy.append(Data([4, 5])) == [Data([0, 1, 4, 5])])
        #expect(original.flush().isEmpty)
        #expect(copy.flush().isEmpty)
    }
}
