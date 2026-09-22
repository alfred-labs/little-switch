import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Credential script output buffering")
struct CredentialScriptOutputBufferTests {
    @Test("Stdout is bounded after every chunk and overflow is reported only once")
    func boundedPrefix() {
        var buffer = CredentialScriptOutputBuffer(retention: .prefix(4))

        let first = buffer.append(Data("ab".utf8))
        #expect(!first)
        #expect(buffer.data == Data("ab".utf8))
        let atLimit = buffer.append(Data("cd".utf8))
        #expect(!atLimit)
        #expect(buffer.data == Data("abcd".utf8))
        #expect(!buffer.exceededLimit)
        let beyondLimit = buffer.append(Data("ef".utf8))
        #expect(beyondLimit)
        #expect(buffer.data == Data("abcd".utf8))
        #expect(buffer.exceededLimit)
        let subsequentExcess = buffer.append(Data(repeating: 120, count: 4_194_304))
        #expect(!subsequentExcess)
        #expect(buffer.data == Data("abcd".utf8))
    }

    @Test("Stderr keeps its bounded tail across small chunks and oversized chunks")
    func boundedSuffix() {
        var buffer = CredentialScriptOutputBuffer(retention: .suffix(4))

        let first = buffer.append(Data("ab".utf8))
        #expect(!first)
        #expect(buffer.data == Data("ab".utf8))
        let beyondLimit = buffer.append(Data("cde".utf8))
        #expect(beyondLimit)
        #expect(buffer.data == Data("bcde".utf8))
        let subsequentExcess = buffer.append(Data("0123456789".utf8))
        #expect(!subsequentExcess)
        #expect(buffer.data == Data("6789".utf8))
        let emptyChunk = buffer.append(Data())
        #expect(!emptyChunk)
        #expect(buffer.data == Data("6789".utf8))
    }

    @Test("An empty retention budget drains without retaining data", arguments: [0, -1])
    func noRetention(limit: Int) {
        for retention in [CredentialScriptOutputBuffer.Retention.prefix(limit), .suffix(limit)] {
            var buffer = CredentialScriptOutputBuffer(retention: retention)
            let emptyChunk = buffer.append(Data())
            #expect(!emptyChunk)
            let discarded = buffer.append(Data("discarded".utf8))
            #expect(discarded)
            #expect(buffer.exceededLimit)
            #expect(buffer.data.isEmpty)
        }
    }
}
