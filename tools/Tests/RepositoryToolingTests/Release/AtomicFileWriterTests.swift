import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Release atomic file replacement")
struct AtomicFileWriterTests {
    @Test("A prepared replacement preserves the file mode and commits complete contents")
    func permissions() throws {
        try withTemporaryDirectory { root in
            let file = root.appendingPathComponent("cask.rb")
            let initial = Data("initial".utf8)
            let updated = Data("updated".utf8)
            try initial.write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)
            let replacement = try AtomicFileWriter.prepare(contents: updated, at: file, expectedContents: initial)
            #expect(try Data(contentsOf: file) == initial)
            try replacement.commit()
            #expect(try Data(contentsOf: file) == updated)
            #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o640)
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["cask.rb"])
        }
    }

    @Test("An identical update does not alter its inode or modification time")
    func unchanged() throws {
        try withTemporaryDirectory { root in
            let file = root.appendingPathComponent("cask.rb")
            let contents = Data("unchanged".utf8)
            try contents.write(to: file)
            let before = try FileManager.default.attributesOfItem(atPath: file.path)
            try AtomicFileWriter.prepare(contents: contents, at: file, expectedContents: contents).commit()
            let after = try FileManager.default.attributesOfItem(atPath: file.path)
            #expect(before[.modificationDate] as? Date == after[.modificationDate] as? Date)
            #expect(before[.systemFileNumber] as? UInt64 == after[.systemFileNumber] as? UInt64)
        }
    }

    @Test("A concurrent cask edit is preserved and abandoned staged files are removed")
    func concurrentEdit() throws {
        try withTemporaryDirectory { root in
            let file = root.appendingPathComponent("cask.rb")
            let original = Data("initial".utf8)
            let concurrent = Data("user edit".utf8)
            try original.write(to: file)
            do {
                let staged = try AtomicFileWriter.prepare(
                    contents: Data("release".utf8), at: file, expectedContents: original)
                try concurrent.write(to: file)
                #expect(throws: ReleaseValidationError.self) { try staged.commit() }
                #expect(try Data(contentsOf: file) == concurrent)
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["cask.rb"])
            #expect(throws: ReleaseValidationError.self) {
                try AtomicFileWriter.prepare(contents: Data(), at: file, expectedContents: original).commit()
            }
        }
    }

    @Test("New output files are guarded and symlink destinations fail closed")
    func newFilesAndSymlinks() throws {
        try withTemporaryDirectory { root in
            let file = root.appendingPathComponent("appcast.xml")
            let content = Data("document".utf8)
            try AtomicFileWriter.prepare(contents: content, at: file, expectedContents: nil).commit()
            #expect(try Data(contentsOf: file) == content)
            #expect(throws: ReleaseValidationError.self) {
                try AtomicFileWriter.prepare(contents: Data(), at: file, expectedContents: nil).commit()
            }
            let link = root.appendingPathComponent("symlink")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
            #expect(throws: ReleaseValidationError.self) {
                try AtomicFileWriter.prepare(contents: Data(), at: link, expectedContents: content).commit()
            }
            #expect(try Data(contentsOf: file) == content)
        }
    }
}
