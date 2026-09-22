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

    @Test("Cancellation before read installation ignores subsequent pipe data")
    func cancelledBeforeReading() async throws {
        let pipe = Pipe()
        let reader = CredentialScriptPipeReader(handle: pipe.fileHandleForReading)
        let read = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await reader.read()
        }
        try await Task.sleep(for: .milliseconds(100))
        pipe.fileHandleForWriting.write(Data("late".utf8))
        pipe.fileHandleForWriting.closeFile()

        #expect(await read.value == Data())
    }

    @Test("A verbose pipe never retains more than the stdout limit")
    func boundsRetainedOutput() async throws {
        let pipe = Pipe()
        let reader = CredentialScriptPipeReader(handle: pipe.fileHandleForReading)
        async let read = reader.read()
        let writer = Task.detached {
            try pipe.fileHandleForWriting.write(contentsOf: Data(repeating: 120, count: 4_194_304))
            try pipe.fileHandleForWriting.close()
        }

        let data = await read
        try await writer.value

        #expect(data == Data(repeating: 120, count: 65_536))
        #expect(reader.exceededLimit)
    }

    @Test("Stderr readers preserve the tail while draining oversized output")
    func retainsTail() async throws {
        let pipe = Pipe()
        let reader = CredentialScriptPipeReader(handle: pipe.fileHandleForReading, retention: .suffix(4))
        async let read = reader.read()
        pipe.fileHandleForWriting.write(Data("long stderr tail".utf8))
        pipe.fileHandleForWriting.closeFile()

        let data = await read
        #expect(data == Data("tail".utf8))
        #expect(reader.exceededLimit)
    }

    @Test("A queued readability callback cannot append after cancellation")
    func callbackAfterCancellation() async throws {
        let pipe = Pipe()
        let reader = CredentialScriptPipeReader(handle: pipe.fileHandleForReading)
        let read = Task { await reader.read() }
        for _ in 0..<100 where pipe.fileHandleForReading.readabilityHandler == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let queuedHandler = try #require(pipe.fileHandleForReading.readabilityHandler)
        read.cancel()
        #expect(await read.value == Data())

        pipe.fileHandleForWriting.write(Data("late".utf8))
        queuedHandler(pipe.fileHandleForReading)
        pipe.fileHandleForWriting.closeFile()

        #expect(pipe.fileHandleForReading.readabilityHandler == nil)
        #expect(await reader.read() == Data())
    }
}
