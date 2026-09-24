import Darwin
import Foundation

enum ChatGPTHistoryPersistence {
    private struct Envelope: Codable {
        var version = 1
        var conversations: [String: ChatGPTStoredConversation]
    }

    private struct Version: Decodable {
        let version: Int
    }

    static func load(fileURL: URL?, limits: ChatGPTHistoryStore.Limits) throws -> [String: ChatGPTStoredConversation] {
        guard let fileURL else { return [:] }
        try rejectSymlinks(fileURL)
        guard let data = try ChatGPTHistoryFileReader.read(fileURL, maximum: limits.storageBytes) else { return [:] }
        let decoder = JSONDecoder()
        guard let version = try? decoder.decode(Version.self, from: data) else {
            throw ChatGPTHistoryError.invalidStorage
        }
        guard version.version == 1 else { throw ChatGPTHistoryError.unsupportedVersion }
        guard var envelope = try? decoder.decode(Envelope.self, from: data) else {
            throw ChatGPTHistoryError.invalidStorage
        }
        guard envelope.conversations.count <= limits.conversations else { throw ChatGPTHistoryError.capacityExceeded }
        for (key, var conversation) in envelope.conversations {
            try ChatGPTHistoryValidation.stored(conversation, key: key, limits: limits)
            for (id, var node) in conversation.nodes where node.status == .inProgress {
                node.status = .cancelled
                conversation.nodes[id] = node
            }
            envelope.conversations[key] = conversation
        }
        return envelope.conversations
    }

    static func save(
        _ conversations: [String: ChatGPTStoredConversation], fileURL: URL?, limits: ChatGPTHistoryStore.Limits
    ) throws {
        let envelope = Envelope(conversations: conversations.filter { !$0.value.temporary })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do { data = try encoder.encode(envelope) } catch { throw ChatGPTHistoryError.invalidStorage }
        guard data.count <= limits.storageBytes else { throw ChatGPTHistoryError.capacityExceeded }
        guard let fileURL else { return }
        try rejectSymlinks(fileURL)
        let parent = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw ChatGPTHistoryError.persistenceFailed
        }
        try rejectSymlinks(fileURL)
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
            try AtomicFileWriter.write(data, to: fileURL, backupDirectory: parent, backupLimit: 0)
        } catch {
            throw ChatGPTHistoryError.persistenceFailed
        }
    }

    private static func rejectSymlinks(_ file: URL) throws {
        guard file.isFileURL else { throw ChatGPTHistoryError.unsafeStorage }
        for url in [file.deletingLastPathComponent(), file] {
            var info = stat()
            if lstat(url.path, &info) == 0 {
                guard info.st_mode & S_IFMT != S_IFLNK else { throw ChatGPTHistoryError.unsafeStorage }
            } else if errno != ENOENT && errno != ENOTDIR {
                throw ChatGPTHistoryError.persistenceFailed
            }
        }
    }

}

enum ChatGPTHistoryFileReader {
    /// Keep descriptor/type/size validation around the read operation, including
    /// the second bound check when another writer grows the opened file.
    static func read(
        _ file: URL,
        maximum: Int,
        readBytes: (FileHandle, Int) throws -> Data? = { try $0.read(upToCount: $1) }
    ) throws -> Data? {
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT || errno == ENOTDIR { return nil }
            if errno == ELOOP { throw ChatGPTHistoryError.unsafeStorage }
            throw ChatGPTHistoryError.persistenceFailed
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw ChatGPTHistoryError.invalidStorage
        }
        guard info.st_size >= 0, info.st_size <= maximum else { throw ChatGPTHistoryError.capacityExceeded }
        let data: Data
        do { data = try readBytes(handle, maximum + 1) ?? Data() } catch {
            throw ChatGPTHistoryError.persistenceFailed
        }
        guard data.count <= maximum else { throw ChatGPTHistoryError.capacityExceeded }
        return data
    }
}
