import Foundation
import Testing

@Suite("Codex provider migration inspection")
struct CodexProviderMigrationInspectionTests {
    @Test("An unreadable unindexed directory aborts before any migration")
    func unreadableDirectory() throws {
        try withTemporaryDirectory { directory in
            let fixture = try CodexProviderMigrationFixture(root: directory)
            let hidden = fixture.root.appendingPathComponent("archived_sessions/unreadable")
            let session = hidden.appendingPathComponent("rollout-hidden.jsonl")
            try fixture.write(CodexProviderMigrationFixture.record(id: "hidden", provider: "old-provider"), to: session)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: hidden.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hidden.path) }
            let result = try fixture.run(["--apply"])
            #expect(result.status != 0)
            #expect(result.stderr.contains("session directory"))
            #expect(try fixture.backups().isEmpty)
            #expect(
                try fixture.contents(fixture.session)
                    == CodexProviderMigrationFixture.record(id: "active", provider: "little-switch"))
        }
    }

    @Test("Configuration changed during header inspection invalidates the migration plan")
    func configurationChangesDuringInspection() throws {
        try withTemporaryDirectory { directory in
            let fixture = try CodexProviderMigrationFixture(root: directory)
            let repository = try RepositoryFixture.root()
            let script = repository.appendingPathComponent("tools/migrations/migrate-codex-provider.sh")
            let probe = fixture.root.appendingPathComponent("inspect.py")
            try fixture.write(Self.configurationProbe, to: probe)
            var interpreter: String?
            for candidate in ["python3", "python3.14", "python3.13", "python3.12", "python3.11"] {
                let result = try RepositoryProcess.run(
                    URL(fileURLWithPath: "/usr/bin/env"),
                    arguments: [candidate, "-c", "import tomllib"],
                    directory: fixture.root)
                if result.status == 0 {
                    interpreter = candidate
                    break
                }
            }
            let python = try #require(interpreter)
            let result = try RepositoryProcess.run(
                URL(fileURLWithPath: "/usr/bin/env"),
                arguments: [python, probe.path, script.path, fixture.root.path],
                directory: fixture.root)
            #expect(result.status == 0, "\(result.stderr)")
            #expect(try fixture.backups().isEmpty)
            #expect(
                try fixture.contents(fixture.session)
                    == CodexProviderMigrationFixture.record(id: "active", provider: "little-switch"))
        }
    }

    private static let configurationProbe = #"""
        from pathlib import Path
        import sys

        source = Path(sys.argv[1]).read_text().split("<<'PYTHON'\n", 1)[1].rsplit("\nPYTHON", 1)[0]
        definitions = source.rsplit("\ntry:\n    main()\n", 1)[0]
        migration = {}
        exec(compile(definitions, sys.argv[1], "exec"), migration)
        root = Path(sys.argv[2]).resolve()
        original_read = migration["read_header"]

        def read_while_configuration_changes(path):
            parsed = original_read(path)
            (root / "config.toml").write_text('model_provider = "other-provider"\n')
            return parsed

        migration["read_header"] = read_while_configuration_changes
        try:
            migration["plan"](root)
        except migration["MigrationError"] as error:
            assert "configuration changed" in str(error).lower()
        else:
            raise AssertionError("Inspection accepted configuration it never validated")
        """#
}
