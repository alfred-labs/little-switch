import Foundation

/// Codex requires an auth file before it runs. When the user has neither a
/// ChatGPT session nor an API key, a local sentinel file unblocks the app
/// without holding any real credential; the gateway rejects the sentinel
/// before any native forwarding. A real auth file is never read, replaced,
/// or removed.
package struct CodexSentinelAuth: Sendable {
    struct Content: Codable, Equatable, Sendable {
        var openAIAPIKey: String
        var authMode: String

        private enum CodingKeys: String, CodingKey {
            case openAIAPIKey = "OPENAI_API_KEY"
            case authMode = "auth_mode"
        }

        func encode(to encoder: any Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(openAIAPIKey, forKey: .openAIAPIKey)
            try values.encode(authMode, forKey: .authMode)
        }
    }

    static let content = Content(
        openAIAPIKey: CodexNativePassthrough.sentinelAPIKey,
        authMode: "apikey"
    )

    let authURL: URL
    private let fileStore: any CodexProfileFileStore

    init(configURL: URL, fileStore: (any CodexProfileFileStore)? = nil) {
        authURL = configURL.deletingLastPathComponent().appending(path: "auth.json")
        self.fileStore =
            fileStore
            ?? DiskCodexProfileFileStore(
                backupDirectory:
                    configURL
                    .deletingLastPathComponent()
                    .appending(path: "auth-backup")
            )
    }

    /// Creates the sentinel only when the auth file is absent. An existing
    /// file — real credentials or user edits — is left byte-identical.
    func installIfAbsent() throws {
        guard try fileStore.snapshot(authURL) == nil else {
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try fileStore.write(try encoder.encode(Self.content), to: authURL)
    }

    static func isManaged(_ data: Data?) -> Bool {
        guard let data else {
            return false
        }
        let decoder = JSONDecoder()
        guard let content = try? decoder.decode(Content.self, from: data),
            content == Self.content
        else {
            return false
        }
        return true
    }

    /// Removes the auth file only when it still contains exactly the
    /// sentinel. Foreign content survives untouched.
    func removeIfManaged() throws {
        guard Self.isManaged(try fileStore.snapshot(authURL)) else {
            return
        }
        try fileStore.restore(nil, to: authURL)
    }
}
