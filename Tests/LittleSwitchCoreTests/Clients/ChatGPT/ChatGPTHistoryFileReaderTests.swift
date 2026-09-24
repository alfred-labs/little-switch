import Foundation
import Testing

@testable import LittleSwitchCore

struct ChatGPTHistoryFileReaderTests {
    @Test func emptyExistingFileIsCorruptRatherThanMissing() throws {
        let directory = historyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "history.json")
        try Data().write(to: file)
        #expect(try ChatGPTHistoryFileReader.read(file, maximum: 64) == Data())
        #expect(throws: ChatGPTHistoryError.invalidStorage) { try ChatGPTHistoryStore(fileURL: file) }
        #expect(try Data(contentsOf: file).isEmpty)
    }

    @Test func fileGrowthBetweenStatAndReadStillEnforcesTheBound() throws {
        let directory = historyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "history.json")
        try Data("a".utf8).write(to: file)
        #expect(throws: ChatGPTHistoryError.capacityExceeded) {
            try ChatGPTHistoryFileReader.read(file, maximum: 1) { handle, maximum in
                let writer = try FileHandle(forWritingTo: file)
                defer { try? writer.close() }
                try writer.seekToEnd()
                try writer.write(contentsOf: Data("b".utf8))
                return try handle.read(upToCount: maximum)
            }
        }
        #expect(try Data(contentsOf: file) == Data("ab".utf8))
    }

    @Test func readFailureIsNormalizedWithoutChangingTheFile() throws {
        let directory = historyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "history.json")
        let bytes = Data("original".utf8)
        try bytes.write(to: file)
        #expect(throws: ChatGPTHistoryError.persistenceFailed) {
            try ChatGPTHistoryFileReader.read(file, maximum: 64) { handle, maximum in
                _ = maximum
                try handle.close()
                return try handle.readToEnd()
            }
        }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func descriptorOpenRejectsSymlinksIndependentlyOfPreflight() throws {
        let directory = historyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appending(path: "target")
        let link = directory.appending(path: "history.json")
        try Data("private".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: ChatGPTHistoryError.unsafeStorage) {
            try ChatGPTHistoryFileReader.read(link, maximum: 64)
        }
        #expect(try Data(contentsOf: target) == Data("private".utf8))
    }
}
