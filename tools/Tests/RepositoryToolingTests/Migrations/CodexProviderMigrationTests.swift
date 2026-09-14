import Foundation
import Testing

@Suite("Codex provider migration")
struct CodexProviderMigrationTests {
    @Test("Default invocation reports legacy sessions without changing files or creating backups")
    func dryRun() throws {
        try withTemporaryDirectory { directory in
            let fixture = try CodexProviderMigrationFixture(root: directory)
            let originals = try [
                fixture.config, fixture.database, fixture.session, fixture.archived, fixture.unrelated,
            ]
            .map { ($0, try Data(contentsOf: $0)) }
            let result = try fixture.run()
            #expect(result.status == 0, "\(result.stderr)")
            #expect(result.stdout.contains("2 database rows"))
            #expect(result.stdout.contains("2 session files"))
            for (url, original) in originals {
                #expect(try Data(contentsOf: url) == original)
            }
            #expect(try fixture.backups().isEmpty)
        }
    }

    @Test("Apply migrates active and archived metadata, preserves content, backs up originals, and is idempotent")
    func apply() throws {
        try withTemporaryDirectory { directory in
            let fixture = try CodexProviderMigrationFixture(root: directory)
            let config = try Data(contentsOf: fixture.config)
            let result = try fixture.run(["--apply"])
            try #require(result.status == 0, "\(result.stderr)")
            #expect(
                try fixture.sql("SELECT id,model_provider,archived,title FROM threads ORDER BY id;").stdout
                    == "active|openai|0|Keep active title\narchived|openai|1|Keep archive title\nunrelated|openai|0|Keep unrelated title\n"
            )
            #expect(try fixture.sql("SELECT * FROM other_state;").stdout == "keep this state\n")
            #expect(try Data(contentsOf: fixture.config) == config)
            #expect(
                try fixture.contents(fixture.unrelated)
                    == CodexProviderMigrationFixture.record(id: "unrelated", provider: "openai"))
            for (url, id) in [(fixture.session, "active"), (fixture.archived, "archived")] {
                #expect(try fixture.contents(url) == CodexProviderMigrationFixture.record(id: id, provider: "openai"))
            }
            let backup = try #require(fixture.backups().first)
            #expect(
                try fixture.contents(backup.appendingPathComponent("sessions/2026/09/14/rollout-active.jsonl"))
                    == CodexProviderMigrationFixture.record(id: "active", provider: "little-switch"))
            #expect(
                try fixture.sql(
                    "SELECT count(*) FROM threads WHERE model_provider='little-switch';",
                    database: backup.appendingPathComponent("state_5.sqlite")
                ).stdout == "2\n")
            let repeated = try fixture.run(["--apply"])
            #expect(repeated.status == 0, "\(repeated.stderr)")
            #expect(try fixture.backups().count == 1)
        }
    }

    @Test("A database rejection restores already edited session files")
    func rollback() throws {
        try withTemporaryDirectory { directory in
            let fixture = try CodexProviderMigrationFixture(root: directory)
            let trigger = try fixture.sql(
                "CREATE TRIGGER refuse_migration BEFORE UPDATE ON threads BEGIN SELECT RAISE(ABORT,'fixture rejection'); END;"
            )
            try #require(trigger.status == 0)
            let result = try fixture.run(["--apply"])
            #expect(result.status != 0)
            #expect(result.stderr.contains("rolled back"))
            #expect(try fixture.backups().count == 1)
            #expect(
                try fixture.contents(fixture.session)
                    == CodexProviderMigrationFixture.record(id: "active", provider: "little-switch"))
            #expect(
                try fixture.contents(fixture.archived)
                    == CodexProviderMigrationFixture.record(id: "archived", provider: "little-switch"))
            #expect(
                try fixture.sql("SELECT count(*) FROM threads WHERE model_provider='little-switch';").stdout == "2\n")
        }
    }

    @Test("Verification failure rolls back metadata when a trigger retains an old provider")
    func verificationRollback() throws {
        try withTemporaryDirectory { directory in
            let fixture = try CodexProviderMigrationFixture(root: directory)
            let trigger = try fixture.sql(
                "CREATE TRIGGER retain_provider AFTER UPDATE ON threads BEGIN UPDATE threads SET model_provider=OLD.model_provider WHERE id=NEW.id; END;"
            )
            try #require(trigger.status == 0)
            let result = try fixture.run(["--apply"])
            #expect(result.status != 0)
            #expect(result.stderr.contains("rolled back"))
            #expect(
                try fixture.contents(fixture.session)
                    == CodexProviderMigrationFixture.record(id: "active", provider: "little-switch"))
            #expect(
                try fixture.sql("SELECT count(*) FROM threads WHERE model_provider='little-switch';").stdout == "2\n")
        }
    }
}
