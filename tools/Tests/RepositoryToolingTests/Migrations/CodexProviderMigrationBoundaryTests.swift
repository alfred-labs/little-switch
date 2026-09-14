import Foundation
import Testing

@Suite("Codex provider migration boundaries")
struct CodexProviderMigrationBoundaryTests {
    @Test(
        "Every legacy provider migrates to openai",
        arguments: [
            "alfred-profile-b1dbe859-198c-5090-9ac3-135d40d36530", "omlx", "custom-provider",
        ])
    func allProviders(provider: String) throws {
        try withTemporaryDirectory { directory in
            let fixture = try CodexProviderMigrationFixture(root: directory)
            try #require(fixture.sql("UPDATE threads SET model_provider='\(provider)' WHERE id='active';").status == 0)
            try fixture.write(
                CodexProviderMigrationFixture.record(id: "active", provider: provider), to: fixture.session)
            let result = try fixture.run(["--apply"])
            #expect(result.status == 0, "\(result.stderr)")
            #expect(try fixture.sql("SELECT count(*) FROM threads WHERE model_provider != 'openai';").stdout == "0\n")
            #expect(
                try fixture.contents(fixture.session)
                    == CodexProviderMigrationFixture.record(id: "active", provider: "openai"))
        }
    }

    @Test("Dry run never creates SQLite WAL sidecars in Codex home")
    func dryRunWAL() throws {
        try withTemporaryDirectory { directory in
            let fixture = try CodexProviderMigrationFixture(root: directory)
            try #require(fixture.sql("PRAGMA journal_mode=WAL;").status == 0)
            let before = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted()
            let result = try fixture.run()
            #expect(result.status == 0, "\(result.stderr)")
            #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted() == before)
        }
    }

    @Test("Unindexed archives migrate while empty unreferenced files remain untouched")
    func unindexedArchive() throws {
        try withTemporaryDirectory { directory in
            let fixture = try CodexProviderMigrationFixture(root: directory)
            let orphan = fixture.root.appendingPathComponent("archived_sessions/rollout-orphan.jsonl")
            let empty = fixture.root.appendingPathComponent("sessions/empty.jsonl")
            try fixture.write(CodexProviderMigrationFixture.record(id: "orphan", provider: "little-switch"), to: orphan)
            try fixture.write("", to: empty)
            let result = try fixture.run(["--apply"])
            #expect(result.status == 0, "\(result.stderr)")
            #expect(result.stdout.contains("3 session files"))
            #expect(
                try fixture.contents(orphan) == CodexProviderMigrationFixture.record(id: "orphan", provider: "openai"))
            #expect(try fixture.contents(empty).isEmpty)
        }
    }

    @Test(
        "Interrupted runs finish whether the database or session header was already migrated", arguments: [true, false])
    func interruptedRun(databaseFirst: Bool) throws {
        try withTemporaryDirectory { directory in
            let fixture = try CodexProviderMigrationFixture(root: directory)
            if databaseFirst {
                try #require(fixture.sql("UPDATE threads SET model_provider='openai' WHERE id='active';").status == 0)
            } else {
                try fixture.write(
                    CodexProviderMigrationFixture.record(id: "active", provider: "openai"), to: fixture.session)
            }
            let result = try fixture.run(["--apply"])
            #expect(result.status == 0, "\(result.stderr)")
            #expect(
                try fixture.sql("SELECT count(*) FROM threads WHERE model_provider='little-switch';").stdout == "0\n")
            #expect(
                try fixture.contents(fixture.session)
                    == CodexProviderMigrationFixture.record(id: "active", provider: "openai"))
        }
    }

    @Test("An open database blocks application before backups or writes")
    func openDatabase() throws {
        try withTemporaryDirectory { directory in
            let fixture = try CodexProviderMigrationFixture(root: directory)
            let handle = try FileHandle(forReadingFrom: fixture.database)
            defer { try? handle.close() }
            let result = try fixture.run(["--apply"])
            #expect(result.status != 0)
            #expect(result.stderr.contains("files are open"))
            #expect(try fixture.backups().isEmpty)
            #expect(
                try fixture.contents(fixture.session)
                    == CodexProviderMigrationFixture.record(id: "active", provider: "little-switch"))
        }
    }

    @Test(
        "Invalid legacy session headers abort before changing any task",
        arguments: [
            "", "not-json\n",
            "{\"type\":\"session_meta\",\"payload\":{\"id\":\"wrong\",\"model_provider\":\"little-switch\"}}\n",
        ])
    func invalidHeader(header: String) throws {
        try withTemporaryDirectory { directory in
            let fixture = try CodexProviderMigrationFixture(root: directory)
            try fixture.write(header, to: fixture.archived)
            let result = try fixture.run(["--apply"])
            #expect(result.status != 0)
            #expect(try fixture.backups().isEmpty)
            #expect(
                try fixture.contents(fixture.session)
                    == CodexProviderMigrationFixture.record(id: "active", provider: "little-switch"))
            #expect(
                try fixture.sql("SELECT count(*) FROM threads WHERE model_provider='little-switch';").stdout == "2\n")
        }
    }

    @Test(
        "Unsupported or inactive configuration aborts without disclosing its content",
        arguments: [
            "model_provider = \"little-switch\"\n",
            "openai_base_url = 42\n",
            "openai_base_url = \"http://127.0.0.1:11436/v1\"\nsqlite_home = \"elsewhere\"\n",
            "invalid fixture_config_value\n",
        ])
    func invalidConfig(config: String) throws {
        try withTemporaryDirectory { directory in
            let fixture = try CodexProviderMigrationFixture(root: directory)
            try fixture.write(config, to: fixture.config)
            let result = try fixture.run(["--apply"])
            #expect(result.status != 0)
            #expect(!result.stderr.contains("Traceback"))
            #expect(!result.stderr.contains("fixture_config_value"))
            #expect(try fixture.backups().isEmpty)
        }
    }

    @Test("A nested provider field and escaped legacy value only change the actual session provider")
    func escapedHeader() throws {
        try withTemporaryDirectory { directory in
            let fixture = try CodexProviderMigrationFixture(root: directory)
            let header =
                #"{"type":"session_meta","payload":{"id":"active","extension":{"model_provider":"little-switch"},"model_provider":"little\u002dswitch"}}"#
            let tail = "\r\nkeep these bytes, including little-switch, unchanged\r\n"
            try fixture.write(header + tail, to: fixture.session)
            let result = try fixture.run(["--apply"])
            #expect(result.status == 0, "\(result.stderr)")
            let expected =
                #"{"type":"session_meta","payload":{"id":"active","extension":{"model_provider":"little-switch"},"model_provider":"openai"}}"#
            #expect(try fixture.contents(fixture.session) == expected + tail)
        }
    }

    @Test("All state database versions migrate and backups preserve the original providers")
    func multipleDatabases() throws {
        try withTemporaryDirectory { directory in
            let fixture = try CodexProviderMigrationFixture(root: directory)
            let older = fixture.root.appendingPathComponent("state_4.sqlite")
            try FileManager.default.copyItem(at: fixture.database, to: older)
            try #require(fixture.sql("PRAGMA journal_mode=WAL;").status == 0)
            let result = try fixture.run(["--apply"])
            #expect(result.status == 0, "\(result.stderr)")
            #expect(result.stdout.contains("4 database rows"))
            #expect(
                try fixture.sql("SELECT count(*) FROM threads WHERE model_provider='little-switch';", database: older)
                    .stdout == "0\n")
            let backup = try #require(fixture.backups().first)
            for name in ["state_4.sqlite", "state_5.sqlite"] {
                let path = backup.appendingPathComponent(name)
                #expect(
                    try fixture.sql(
                        "PRAGMA quick_check; SELECT count(*) FROM threads WHERE model_provider='little-switch';",
                        database: path
                    ).stdout == "ok\n2\n")
                let permissions = try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? Int
                #expect(permissions == 0o600)
            }
        }
    }

    @Test("Dry run reads committed WAL data without writes and apply backs it up")
    func uncheckpointedWAL() throws {
        try withTemporaryDirectory { directory in
            let fixture = try CodexProviderMigrationFixture(root: directory)
            let setup = try fixture.sql(
                "PRAGMA journal_mode=WAL; UPDATE threads SET model_provider='wal-provider' WHERE id='unrelated';",
                options: ["-cmd", ".dbconfig no_ckpt_on_close on"])
            try #require(setup.status == 0, "\(setup.stderr)")
            let wal = URL(fileURLWithPath: fixture.database.path + "-wal")
            let shared = URL(fileURLWithPath: fixture.database.path + "-shm")
            let original = try [fixture.database, wal, shared].map { ($0, try Data(contentsOf: $0)) }
            let simulation = try fixture.run()
            #expect(simulation.status == 0, "\(simulation.stderr)")
            #expect(simulation.stdout.contains("3 database rows"))
            for (url, data) in original {
                #expect(try Data(contentsOf: url) == data)
            }
            let result = try fixture.run(["--apply"])
            #expect(result.status == 0, "\(result.stderr)")
            let backup = try #require(fixture.backups().first)
            #expect(
                try fixture.sql(
                    "SELECT model_provider FROM threads WHERE id='unrelated';",
                    database: backup.appendingPathComponent("state_5.sqlite")
                ).stdout == "wal-provider\n")
        }
    }
}
