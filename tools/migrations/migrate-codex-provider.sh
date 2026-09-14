#!/bin/bash
# Migrate every saved Codex provider to openai after activating LittleSwitch 0.5.0.
# Standalone: Bash + Python 3.11 or newer, using only the standard library.
set -euo pipefail

for migration_python in python3 python3.14 python3.13 python3.12 python3.11; do
    if command -v "$migration_python" >/dev/null 2>&1 &&
        "$migration_python" -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null; then
        break
    fi
    migration_python=''
done
if [[ -z "$migration_python" ]]; then
    printf '%s\n' 'Python 3.11 or newer is required. No files were changed.' >&2
    exit 1
fi

exec "$migration_python" - "$@" <<'PYTHON'
import argparse
import contextlib
import copy
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile
import tomllib

NEW = "openai"
MAX_HEADER = 64 * 1024 * 1024


class MigrationError(Exception):
    pass


def fail(message):
    raise MigrationError(message)


def regular_file(path, root):
    if not path.is_relative_to(root) or path.resolve() != path:
        fail("A migration file is outside Codex home or uses a symbolic link.")
    info = path.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        fail("A migration file must be regular and have exactly one hard link.")
    return info


def fingerprint(path):
    info = path.stat()
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns)


def database_rows(connection):
    return connection.execute(
        "SELECT id, rollout_path, model_provider FROM threads WHERE model_provider IS NOT ? ORDER BY id",
        (NEW,),
    ).fetchall()


def connect(path, mode):
    return sqlite3.connect(path.as_uri() + "?mode=" + mode, timeout=2, uri=True)


@contextlib.contextmanager
def inspection_database(path, root):
    # Even mode=ro can create WAL sidecars. Inspect a private, stable DB/WAL copy
    # so simulation never opens the user's SQLite files through SQLite itself.
    wal = Path(str(path) + "-wal")
    for _ in range(3):
        with tempfile.TemporaryDirectory(prefix="little-switch-codex-inspect-") as directory:
            source_paths = [path] + ([wal] if wal.exists() else [])
            before = {source: fingerprint(source) for source in source_paths}
            snapshot = Path(directory) / path.name
            for source in source_paths:
                regular_file(source, root)
                durable_copy(source, Path(directory) / source.name)
            if any(not source.exists() or fingerprint(source) != stamp
                   for source, stamp in before.items()) or wal.exists() != (wal in before):
                continue
            with contextlib.closing(connect(snapshot, "ro")) as connection:
                yield connection
            return
    fail("A database changed during inspection. Close Codex and retry.")


def read_header(path):
    with path.open("rb") as stream:
        raw = stream.readline(MAX_HEADER)
    if len(raw) == MAX_HEADER:
        fail("A session header is too large to migrate safely.")
    try:
        record = json.loads(raw)
        if not isinstance(record, dict) or record.get("type") != "session_meta":
            return None
        payload = record.get("payload")
        if not isinstance(payload, dict) or not isinstance(payload.get("id"), str):
            return None
        return raw, record
    except (ValueError, UnicodeError):
        return None


def plan(root):
    config_path = root / "config.toml"
    regular_file(config_path, root)
    config_fingerprint = fingerprint(config_path)
    with config_path.open("rb") as stream:
        config = tomllib.load(stream)
    endpoint = config.get("openai_base_url")
    if (not isinstance(endpoint, str) or endpoint.rstrip("/") != "http://127.0.0.1:11436/v1"
            or config.get("model_provider", NEW) != NEW or config.get("profile")):
        fail("Activate the Codex integration in LittleSwitch 0.5.0 or newer first.")
    if config.get("sqlite_home") or os.environ.get("CODEX_SQLITE_HOME"):
        fail("A separate SQLite home is configured; this script only supports databases in Codex home.")

    databases = []
    required = {}
    for path in sorted(root.glob("state_*.sqlite")):
        if not re.fullmatch(r"state_\d+\.sqlite", path.name):
            continue
        regular_file(path, root)
        with inspection_database(path, root) as connection:
            columns = {row[1] for row in connection.execute("PRAGMA table_info(threads)")}
            if not {"id", "model_provider", "rollout_path"}.issubset(columns):
                fail("An unsupported Codex database schema was found.")
            if connection.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
                fail("A Codex database failed its integrity check.")
            rows = database_rows(connection)
        databases.append((path, rows))
        for thread_id, rollout_path, provider in rows:
            if not isinstance(rollout_path, str):
                fail("A legacy task has no session file path.")
            session = Path(rollout_path)
            if not session.is_absolute():
                session = root / session
            if session.is_symlink():
                fail("A legacy task uses a symbolic link for its session file.")
            # macOS may record /var/... while the same Codex home resolves to /private/var/...
            session = session.resolve(strict=True)
            regular_file(session, root)
            if session.suffix != ".jsonl":
                fail("A legacy task uses an unsupported session format.")
            required.setdefault(session, set()).add(thread_id)

    candidates = set(required)
    for folder in (root / "sessions", root / "archived_sessions"):
        if not folder.exists():
            continue
        for directory, subdirs, files in os.walk(
            folder, followlinks=False,
            onerror=lambda _: fail("A session directory could not be read; no migration was started."),
        ):
            if Path(directory).resolve() != Path(directory) or any(
                (Path(directory) / name).is_symlink() for name in subdirs
            ):
                fail("A session directory uses a symbolic link.")
            for name in files:
                if name.endswith(".jsonl.zst"):
                    fail("Compressed sessions are not supported by this migration script.")
                if name.endswith(".jsonl"):
                    candidates.add(Path(directory) / name)

    sessions = []
    skipped = 0
    for path in sorted(candidates):
        regular_file(path, root)
        before = fingerprint(path)
        parsed = read_header(path)
        if parsed is None:
            if path in required:
                fail("A legacy task has an invalid session header; no migration was started.")
            skipped += 1
            continue
        raw, record = parsed
        payload = record["payload"]
        provider = payload.get("model_provider")
        if provider is not None and not isinstance(provider, str):
            fail("A session header has an unsupported provider value.")
        if path in required and required[path] != {payload["id"]}:
            fail("A legacy task disagrees with its session header; no migration was started.")
        if provider is None or provider == NEW:
            continue
        updated = copy.deepcopy(record)
        updated["payload"]["model_provider"] = NEW
        # Target only the JSON property, even when instructions contain the same text.
        pattern = rb'("model_provider"\s*:\s*)' + re.escape(json.dumps(provider).encode())
        header = re.sub(pattern, rb'\1"openai"', raw, count=1)
        if json.loads(header) != updated:
            # Escaped JSON keys/values or an earlier nested field need structural encoding.
            ending = b"\r\n" if raw.endswith(b"\r\n") else b"\n" if raw.endswith(b"\n") else b""
            header = json.dumps(updated, ensure_ascii=False, separators=(",", ":")).encode() + ending
        if fingerprint(path) != before:
            fail("A session changed during inspection. Close Codex and retry.")
        sessions.append((path, raw, header, before))
    if fingerprint(config_path) != config_fingerprint:
        fail("Codex configuration changed during inspection. Close Codex and retry.")
    return databases, sessions, skipped, config_fingerprint


def ensure_idle(paths):
    lsof = shutil.which("lsof") or "/usr/sbin/lsof"
    paths = [str(path) for path in paths if path.exists()]
    for offset in range(0, len(paths), 100):
        result = subprocess.run([lsof, "-t", "--"] + paths[offset:offset + 100],
                                capture_output=True, text=True, timeout=30)
        if result.returncode not in (0, 1) or result.stderr:
            fail("Cannot check for open Codex files. Close Codex and run from Terminal.")
        if any(pid != str(os.getpid()) for pid in result.stdout.split()):
            fail("Codex files are open. Quit Codex and its CLI sessions, then run --apply from Terminal.")


def durable_copy(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with source.open("rb") as reader, destination.open("xb") as writer:
        os.chmod(destination, 0o600)
        shutil.copyfileobj(reader, writer)
        writer.flush()
        os.fsync(writer.fileno())


def replace_session(path, source, original_header, header):
    mode = stat.S_IMODE(path.stat().st_mode)
    descriptor, temporary = tempfile.mkstemp(prefix=".little-switch-migration-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as writer, source.open("rb") as reader:
            if reader.read(len(original_header)) != original_header:
                fail("A session changed after inspection. Close Codex and retry.")
            writer.write(header)
            shutil.copyfileobj(reader, writer)
            writer.flush()
            os.fchmod(writer.fileno(), mode)
            os.fsync(writer.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def apply(root, databases, sessions, config_fingerprint):
    watched = [root / "config.toml"] + [item[0] for item in sessions]
    for path, _ in databases:
        watched.extend([path, Path(str(path) + "-wal"), Path(str(path) + "-shm")])
    ensure_idle(watched)
    backup_parent = root / "little-switch-provider-backups"
    if backup_parent.is_symlink():
        fail("The backup directory uses a symbolic link.")
    backup_parent.mkdir(mode=0o700, exist_ok=True)
    backup = Path(tempfile.mkdtemp(prefix="migration-", dir=backup_parent))
    print("Backup: " + str(backup), flush=True)
    changed = []
    committed = []
    connections = []
    try:
        for path, rows in databases:
            connection = connect(path, "rw")
            connections.append((connection, path, rows))
            connection.execute("BEGIN IMMEDIATE")
            if database_rows(connection) != rows:
                fail("A database changed after inspection. Close Codex and retry.")
            # The writer lock prevents changes while a separate reader takes a WAL-aware backup.
            with contextlib.closing(connect(path, "ro")) as reader:
                with contextlib.closing(sqlite3.connect(backup / path.name)) as destination:
                    reader.backup(destination)
            os.chmod(backup / path.name, 0o600)
        for path, raw, header, before in sessions:
            if fingerprint(path) != before:
                fail("A session changed after inspection. Close Codex and retry.")
            durable_copy(path, backup / path.relative_to(root))
            if fingerprint(path) != before:
                fail("A session changed during backup. Close Codex and retry.")
        if fingerprint(root / "config.toml") != config_fingerprint:
            fail("Codex configuration changed after inspection. Close Codex and retry.")
        ensure_idle(watched)
        manifest = {"codex_home": str(root), "to": NEW,
                    "databases": [path.name for path, _ in databases],
                    "sessions": [str(path.relative_to(root)) for path, *_ in sessions]}
        (backup / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        for path, raw, header, before in sessions:
            if fingerprint(path) != before:
                fail("A session changed before writing. Close Codex and retry.")
            changed.append((path, raw, header))
            replace_session(path, backup / path.relative_to(root), raw, header)
        for connection, path, rows in connections:
            count = connection.execute("UPDATE threads SET model_provider = ? WHERE model_provider IS NOT ?",
                                       (NEW, NEW)).rowcount
            if (count != len(rows) or database_rows(connection)
                    or connection.execute("PRAGMA quick_check").fetchall() != [("ok",)]):
                fail("Database verification failed.")
        for path, raw, header, before in sessions:
            with path.open("rb") as stream:
                if stream.read(len(header)) != header or path.stat().st_size != before[2] - len(raw) + len(header):
                    fail("Session verification failed.")
        for connection, path, rows in connections:
            committed.append((connection, rows))
            connection.commit()
        for connection, _, _ in connections:
            if database_rows(connection):
                fail("Committed database verification failed.")
    except BaseException:
        rollback_failed = False
        for connection, _, _ in connections:
            try:
                connection.rollback()
            except sqlite3.Error:
                rollback_failed = True
        for connection, rows in committed:
            try:
                connection.executemany("UPDATE threads SET model_provider = ? WHERE id = ? AND model_provider = ?",
                                       [(provider, thread_id, NEW) for thread_id, _, provider in rows])
                connection.commit()
            except sqlite3.Error:
                rollback_failed = True
        for path, raw, header in reversed(changed):
            try:
                replace_session(path, backup / path.relative_to(root), raw, raw)
            except (OSError, MigrationError):
                rollback_failed = True
        if rollback_failed:
            print("Rollback incomplete. Keep Codex closed and recover from the backup above.", file=sys.stderr)
        else:
            print("Migration rolled back; original data preserved.", file=sys.stderr)
        raise
    finally:
        for connection, _, _ in connections:
            connection.close()


def main():
    parser = argparse.ArgumentParser(prog="migrate-codex-provider.sh",
                                     description="Migrate ALL saved Codex providers to openai for LittleSwitch 0.5.0+.")
    parser.add_argument("--codex-home", type=Path, default=Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")))
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true", help="back up and migrate; close Codex first")
    mode.add_argument("--dry-run", action="store_true", help="inspect only (default)")
    args = parser.parse_args()
    root = args.codex_home.expanduser().resolve(strict=True)
    os.umask(0o077)
    databases, sessions, skipped, config_fingerprint = plan(root)
    count = sum(len(rows) for _, rows in databases)
    print(f"Found {count} database rows and {len(sessions)} session files to migrate.")
    if skipped:
        print(f"Skipped {skipped} empty or unrecognized headers not referenced by legacy tasks.")
    if not count and not sessions:
        print("No migration needed.")
    elif args.apply:
        apply(root, databases, sessions, config_fingerprint)
        print("Migration verified. Reopen Codex and resume an old task.")
    else:
        print("Dry run: no files changed. Quit Codex, then rerun with --apply from Terminal.")


try:
    main()
except (MigrationError, OSError, sqlite3.Error, tomllib.TOMLDecodeError,
        subprocess.SubprocessError, KeyboardInterrupt) as error:
    # Never echo config content, SQL values, or session bodies on an error.
    detail = str(error) if isinstance(error, MigrationError) else type(error).__name__
    print("Error: " + detail, file=sys.stderr)
    sys.exit(1)
PYTHON
