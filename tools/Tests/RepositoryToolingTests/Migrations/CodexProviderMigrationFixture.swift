import Foundation
import Testing

struct CodexProviderMigrationFixture {
    let root: URL
    let database: URL
    let session: URL
    let archived: URL
    let unrelated: URL
    let config: URL

    init(root: URL) throws {
        self.root = root.resolvingSymlinksInPath()
        database = self.root.appendingPathComponent("state_5.sqlite")
        session = self.root.appendingPathComponent("sessions/2026/09/14/rollout-active.jsonl")
        archived = self.root.appendingPathComponent("archived_sessions/rollout-archived.jsonl")
        unrelated = self.root.appendingPathComponent("sessions/rollout-unrelated.jsonl")
        config = self.root.appendingPathComponent("config.toml")
        try write(
            "openai_base_url = \"http://127.0.0.1:11436/v1\"\nmodel = \"example/model\"\n",
            to: config)
        try write(Self.record(id: "active", provider: "little-switch"), to: session)
        try write(Self.record(id: "archived", provider: "little-switch"), to: archived)
        try write(Self.record(id: "unrelated", provider: "openai"), to: unrelated)
        let result = try sql(
            """
            CREATE TABLE threads (
              id TEXT PRIMARY KEY, model_provider TEXT NOT NULL, rollout_path TEXT NOT NULL,
              archived INTEGER NOT NULL, title TEXT NOT NULL
            );
            INSERT INTO threads VALUES
              ('active','little-switch',\(quote(session.path)),0,'Keep active title'),
              ('archived','little-switch',\(quote(archived.path)),1,'Keep archive title'),
              ('unrelated','openai',\(quote(unrelated.path)),0,'Keep unrelated title');
            CREATE TABLE other_state (value TEXT);
            INSERT INTO other_state VALUES ('keep this state');
            """)
        try #require(result.status == 0, "\(result.stderr)")
    }

    func run(_ arguments: [String] = []) throws -> RepositoryProcess.Result {
        let repository = try RepositoryFixture.root()
        let script = repository.appendingPathComponent("tools/migrations/migrate-codex-provider.sh")
        return try RepositoryProcess.run(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [script.path, "--codex-home", root.path] + arguments,
            directory: repository)
    }

    func sql(
        _ statement: String,
        database override: URL? = nil,
        options: [String] = []
    ) throws -> RepositoryProcess.Result {
        try RepositoryProcess.run(
            URL(fileURLWithPath: "/usr/bin/sqlite3"),
            arguments: options + [(override ?? database).path, statement],
            directory: root)
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func contents(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func backups() throws -> [URL] {
        let directory = root.appendingPathComponent("little-switch-provider-backups")
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    }

    static func record(id: String, provider: String) -> String {
        """
        {"type":"session_meta","payload":{"id":"\(id)","model_provider":"\(provider)","model":"example/model",\
        "base_instructions":{"text":"Keep little-switch in instructions"},"extension":{"model_provider":"little-switch"}}}
        {"type":"response_item","payload":{"text":"little-switch","model_provider":"little-switch"}}

        """
    }

    private func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
    }
}
