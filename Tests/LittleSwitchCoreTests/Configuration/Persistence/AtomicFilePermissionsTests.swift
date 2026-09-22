import Darwin
import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Atomic file permissions")
struct AtomicFilePermissionsTests {
    @Test("Private permissions protect the empty temporary file and its published contents")
    func privateFromCreation() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "settings.json")
        try Data("before".utf8).write(to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        let fileManager = InspectingAtomicFileManager()

        try AtomicFileWriter.write(
            Data("after".utf8),
            to: destination,
            backupDirectory: directory.appending(path: "backups"),
            fileManager: fileManager
        )

        #expect(fileManager.createdModes == [0o600])
        #expect(fileManager.createdContents == [Data()])
        #expect(try permissions(of: destination) == 0o600)
        #expect(try Data(contentsOf: destination) == Data("after".utf8))
    }

    @Test("Explicit restore permissions apply before publication", arguments: [0o400, 0o640, 0o644])
    func restoredPermissions(mode: Int) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "settings.json")
        let fileManager = InspectingAtomicFileManager()

        try AtomicFileWriter.write(
            Data("restored".utf8),
            to: destination,
            backupDirectory: directory.appending(path: "backups"),
            permissions: mode,
            fileManager: fileManager
        ) { source, destination in
            #expect((try? permissions(of: source)) == mode)
            return Darwin.rename(source.path, destination.path) == 0 ? 0 : errno
        }

        #expect(fileManager.createdModes == [0o600])
        #expect(fileManager.createdContents == [Data()])
        #expect(try permissions(of: destination) == mode)
        #expect(try Data(contentsOf: destination) == Data("restored".utf8))
    }

    @Test("A failed temporary creation preserves the destination")
    func failedCreation() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "settings.json")
        try Data("before".utf8).write(to: destination)

        #expect(throws: CocoaError.self) {
            try AtomicFileWriter.write(
                Data("after".utf8),
                to: destination,
                backupDirectory: directory.appending(path: "backups"),
                fileManager: CreationRejectingAtomicFileManager()
            )
        }

        #expect(try Data(contentsOf: destination) == Data("before".utf8))
    }

    @Test("Claude Desktop writes and rollback restores keep MCP content private")
    func desktopProfilePermissions() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "settings.json")
        let store = DiskClaudeProfileFileStore(backupDirectory: directory.appending(path: "backups"))
        try store.writeObject(["mcpServers": ["fixture": ["env": ["KEY": "synthetic"]]]], to: destination)
        #expect(try permissions(of: destination) == 0o600)
        let original = try Data(contentsOf: destination)

        try store.restore(original, to: destination)

        #expect(try permissions(of: destination) == 0o600)
        #expect(try Data(contentsOf: destination) == original)
    }
}

private final class InspectingAtomicFileManager: FileManager, @unchecked Sendable {
    private(set) var createdModes: [Int] = []
    private(set) var createdContents: [Data] = []

    override func createFile(
        atPath path: String,
        contents data: Data?,
        attributes attr: [FileAttributeKey: Any]? = nil
    ) -> Bool {
        let created = super.createFile(atPath: path, contents: data, attributes: attr)
        guard let attributes = try? attributesOfItem(atPath: path),
            let mode = attributes[.posixPermissions] as? NSNumber,
            let contents = try? Data(contentsOf: URL(filePath: path))
        else {
            return created
        }
        createdModes.append(mode.intValue)
        createdContents.append(contents)
        return created
    }
}

private final class CreationRejectingAtomicFileManager: FileManager, @unchecked Sendable {
    override func createFile(
        atPath path: String,
        contents data: Data?,
        attributes attr: [FileAttributeKey: Any]? = nil
    ) -> Bool {
        false
    }
}
