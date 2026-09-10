import Foundation
import Testing

@testable import LittleSwitchCore

/// The cancellation-stoppable pipe reader's own contract, driven through a
/// real pipe: chunks accumulate until EOF, and only one reader may park on
/// the handle at a time.
@Suite("Credential script pipe reader")
struct CredentialScriptPipeReaderTests {

    @Test("Chunks accumulate across handler firings until EOF delivers them")
    func accumulatesUntilEOF() async throws {
        let pipe = Pipe()
        let reader = CredentialScriptPipeReader(handle: pipe.fileHandleForReading)

        async let read = reader.read()
        try await Task.sleep(for: .milliseconds(50))
        pipe.fileHandleForWriting.write(Data("abc".utf8))
        pipe.fileHandleForWriting.write(Data("def".utf8))
        pipe.fileHandleForWriting.closeFile()

        let data = await read
        #expect(try #require(String(data: data, encoding: .utf8)) == "abcdef")
    }

    @Test("A second read while the first is parked returns empty immediately")
    func secondReadReturnsEmpty() async throws {
        let pipe = Pipe()
        let reader = CredentialScriptPipeReader(handle: pipe.fileHandleForReading)

        async let first = reader.read()
        try await Task.sleep(for: .milliseconds(50))

        // The parked first read owns the handle's continuation; the second
        // must bow out empty instead of taking it over.
        let second = await reader.read()
        #expect(second.isEmpty)

        pipe.fileHandleForWriting.write(Data("payload".utf8))
        pipe.fileHandleForWriting.closeFile()
        let firstData = await first
        #expect(try #require(String(data: firstData, encoding: .utf8)) == "payload")
    }
}
