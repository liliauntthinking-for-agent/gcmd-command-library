#!/usr/bin/env python3
"""A small local-first command library for terminal users."""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import subprocess
import sys
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


APP_NAME = "gcmd"
DEFAULT_DATA_DIR = Path.home() / "Library" / "Application Support" / APP_NAME


def data_dir() -> Path:
    override = os.environ.get("GCMD_HOME")
    return Path(override).expanduser() if override else DEFAULT_DATA_DIR


def db_path() -> Path:
    return data_dir() / "commands.sqlite3"


def config_path() -> Path:
    return data_dir() / "config.json"


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def json_copy(value: Any) -> Any:
    return json.loads(json.dumps(value, sort_keys=True))


def connect() -> sqlite3.Connection:
    data_dir().mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(db_path())
    connection.row_factory = sqlite3.Row
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS commands (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            command TEXT NOT NULL,
            shell TEXT NOT NULL,
            cwd TEXT,
            tags TEXT NOT NULL DEFAULT '[]',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT
        )
        """
    )
    connection.commit()
    return connection


@contextmanager
def database() -> Any:
    connection = connect()
    try:
        yield connection
    finally:
        connection.close()


def config() -> dict[str, Any]:
    path = config_path()
    if not path.exists():
        return {}
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def write_config(value: dict[str, Any]) -> None:
    data_dir().mkdir(parents=True, exist_ok=True)
    config_path().write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def row_to_record(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "title": row["title"],
        "command": row["command"],
        "shell": row["shell"],
        "cwd": row["cwd"],
        "tags": json.loads(row["tags"]),
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
        "deleted_at": row["deleted_at"],
    }


def record_to_values(record: dict[str, Any]) -> tuple[Any, ...]:
    return (
        record["id"],
        record["title"],
        record["command"],
        record.get("shell") or "zsh",
        record.get("cwd"),
        json.dumps(record.get("tags") or [], ensure_ascii=False, sort_keys=True),
        record["created_at"],
        record["updated_at"],
        record.get("deleted_at"),
    )


def record_key(record: dict[str, Any] | None) -> str | None:
    if record is None:
        return None
    return json.dumps(record, ensure_ascii=False, sort_keys=True)


def all_records(connection: sqlite3.Connection, include_deleted: bool = True) -> dict[str, dict[str, Any]]:
    query = "SELECT * FROM commands"
    if not include_deleted:
        query += " WHERE deleted_at IS NULL"
    return {row["id"]: row_to_record(row) for row in connection.execute(query)}


def search_records(
    connection: sqlite3.Connection,
    query: str = "",
    include_deleted: bool = False,
    shell: str | None = None,
) -> list[dict[str, Any]]:
    records = list(all_records(connection, include_deleted).values())
    if shell:
        records = [record for record in records if record["shell"] in {shell, "any"}]
    normalized = query.strip().lower()
    if normalized:
        records = [
            record
            for record in records
            if normalized
            in " ".join(
                [
                    record["title"],
                    record["command"],
                    record["shell"],
                    " ".join(record["tags"]),
                ]
            ).lower()
        ]
    return sorted(records, key=lambda item: (item["title"].lower(), item["updated_at"]))


def save_record(connection: sqlite3.Connection, record: dict[str, Any]) -> None:
    connection.execute(
        """
        INSERT INTO commands
            (id, title, command, shell, cwd, tags, created_at, updated_at, deleted_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title=excluded.title,
            command=excluded.command,
            shell=excluded.shell,
            cwd=excluded.cwd,
            tags=excluded.tags,
            created_at=excluded.created_at,
            updated_at=excluded.updated_at,
            deleted_at=excluded.deleted_at
        """,
        record_to_values(record),
    )


def title_for(command: str) -> str:
    first_line = command.strip().splitlines()[0]
    return first_line if len(first_line) <= 72 else first_line[:69] + "..."


def parse_tags(value: str | None) -> list[str]:
    if not value:
        return []
    return sorted({item.strip() for item in value.split(",") if item.strip()})


def add_command(args: argparse.Namespace) -> int:
    command = args.command
    if args.stdin:
        command = sys.stdin.read().strip()
    if not command:
        print("gcmd: command is required", file=sys.stderr)
        return 2

    now = utc_now()
    record = {
        "id": str(uuid.uuid4()),
        "title": args.title or title_for(command),
        "command": command,
        "shell": args.shell or Path(os.environ.get("SHELL", "zsh")).name,
        "cwd": args.cwd or os.getcwd(),
        "tags": parse_tags(args.tags),
        "created_at": now,
        "updated_at": now,
        "deleted_at": None,
    }
    with database() as connection:
        connection.execute(
            "DELETE FROM commands WHERE command = ? AND deleted_at IS NULL",
            (command,),
        )
        save_record(connection, record)
        connection.commit()
    print(f"saved {record['id']}  {record['title']}")
    return 0


def list_commands(args: argparse.Namespace) -> int:
    with database() as connection:
        records = search_records(connection, args.query or "", args.all)
    if args.json:
        print(json.dumps(records, ensure_ascii=False, indent=2))
        return 0
    for record in records:
        deleted = " [deleted]" if record["deleted_at"] else ""
        print(f"{record['id']}  {record['title']}{deleted}")
        print(f"  {record['command']}")
    if not records:
        print("No commands found.")
    return 0


def pick_command(args: argparse.Namespace) -> int:
    with database() as connection:
        query = args.query or ""
        while True:
            records = search_records(connection, query, shell=args.shell)
            print("", file=sys.stderr)
            if query:
                print(f"Search: {query}", file=sys.stderr)
            if not records:
                print("No commands found.", file=sys.stderr)
                return 1
            for index, record in enumerate(records, start=1):
                tags = f" [{', '.join(record['tags'])}]" if record["tags"] else ""
                print(f"{index:>2}. {record['title']}{tags}", file=sys.stderr)
                print(f"     {record['command']}", file=sys.stderr)
            print("", file=sys.stderr)
            print("Search term, number, or Enter for the first result: ", end="", file=sys.stderr, flush=True)
            answer = sys.stdin.readline().strip()
            if not answer:
                chosen = records[0]
                break
            if answer.isdigit() and 1 <= int(answer) <= len(records):
                chosen = records[int(answer) - 1]
                break
            query = answer
        print(chosen["command"])
    return 0


def delete_command(args: argparse.Namespace) -> int:
    now = utc_now()
    with database() as connection:
        cursor = connection.execute(
            "UPDATE commands SET deleted_at = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL",
            (now, now, args.id),
        )
        connection.commit()
    if cursor.rowcount == 0:
        print(f"gcmd: active command not found: {args.id}", file=sys.stderr)
        return 1
    print(f"deleted {args.id}")
    return 0


def sync_dir_from_args(args: argparse.Namespace) -> Path:
    path = args.directory or config().get("sync_dir")
    if not path:
        raise ValueError("sync directory is not configured; run `gcmd sync init PATH` first")
    return Path(path).expanduser().resolve()


def sync_commands_dir(sync_dir: Path) -> Path:
    return sync_dir / "commands"


def read_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return default


def read_remote(sync_dir: Path) -> dict[str, dict[str, Any]]:
    directory = sync_commands_dir(sync_dir)
    if not directory.exists():
        return {}
    records: dict[str, dict[str, Any]] = {}
    for path in directory.glob("*.json"):
        value = read_json(path, None)
        if isinstance(value, dict) and value.get("id"):
            records[value["id"]] = value
    return records


def write_remote(sync_dir: Path, records: dict[str, dict[str, Any]]) -> None:
    directory = sync_commands_dir(sync_dir)
    directory.mkdir(parents=True, exist_ok=True)
    expected = {f"{record_id}.json" for record_id in records}
    for path in directory.glob("*.json"):
        if path.name not in expected:
            path.unlink()
    for record_id, record in records.items():
        path = directory / f"{record_id}.json"
        path.write_text(json.dumps(record, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def load_sync_state(sync_dir: Path) -> dict[str, dict[str, Any]]:
    value = read_json(sync_dir / ".gcmd-state.json", {})
    return value if isinstance(value, dict) else {}


def write_sync_state(sync_dir: Path, records: dict[str, dict[str, Any]]) -> None:
    (sync_dir / ".gcmd-state.json").write_text(
        json.dumps(records, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    )


def make_conflict(remote: dict[str, Any], original_id: str) -> dict[str, Any]:
    conflict = json_copy(remote)
    conflict["id"] = str(uuid.uuid4())
    conflict["title"] = f"{remote['title']} (conflict copy)"
    conflict["tags"] = sorted(set(remote.get("tags", [])) | {"conflict"})
    conflict["updated_at"] = utc_now()
    conflict["conflict_of"] = original_id
    return conflict


def merge_records(
    local: dict[str, dict[str, Any]],
    remote: dict[str, dict[str, Any]],
    base: dict[str, dict[str, Any]],
) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]]]:
    merged: dict[str, dict[str, Any]] = {}
    conflicts: list[dict[str, Any]] = []
    for record_id in sorted(set(local) | set(remote) | set(base)):
        local_record = local.get(record_id)
        remote_record = remote.get(record_id)
        base_record = base.get(record_id)
        if record_key(local_record) == record_key(remote_record):
            if local_record:
                merged[record_id] = local_record
            continue
        # A missing local row means a fresh device or a cleared local database.
        # Tombstones remain rows, so this does not hide intentional deletions.
        if local_record is None and remote_record is not None:
            merged[record_id] = remote_record
            continue
        if remote_record is None and local_record is not None:
            merged[record_id] = local_record
            continue
        if base_record is not None:
            local_changed = record_key(local_record) != record_key(base_record)
            remote_changed = record_key(remote_record) != record_key(base_record)
            if local_changed and remote_changed and local_record and remote_record:
                merged[record_id] = local_record
                conflicts.append(make_conflict(remote_record, record_id))
            elif local_changed:
                if local_record:
                    merged[record_id] = local_record
            elif remote_changed:
                if remote_record:
                    merged[record_id] = remote_record
            elif local_record:
                merged[record_id] = local_record
            continue
        if local_record and remote_record:
            local_time = local_record.get("updated_at", "")
            remote_time = remote_record.get("updated_at", "")
            merged[record_id] = local_record if local_time >= remote_time else remote_record
        elif local_record:
            merged[record_id] = local_record
        elif remote_record:
            merged[record_id] = remote_record
    for conflict in conflicts:
        merged[conflict["id"]] = conflict
    return merged, conflicts


def git_call(sync_dir: Path, *arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(sync_dir), *arguments],
        check=check,
        text=True,
        capture_output=True,
    )


def sync_repository(args: argparse.Namespace) -> int:
    try:
        sync_dir = sync_dir_from_args(args)
    except ValueError as error:
        print(f"gcmd: {error}", file=sys.stderr)
        return 2
    sync_dir.mkdir(parents=True, exist_ok=True)
    sync_commands_dir(sync_dir).mkdir(parents=True, exist_ok=True)

    if args.git:
        if not (sync_dir / ".git").exists():
            print(f"gcmd: not a Git repository: {sync_dir}", file=sys.stderr)
            return 2
        pull = git_call(sync_dir, "pull", "--rebase", check=False)
        if pull.returncode != 0:
            print(pull.stderr.strip() or "git pull failed", file=sys.stderr)
            return 1

    with database() as connection:
        local = all_records(connection, include_deleted=True)
        remote = read_remote(sync_dir)
        base = load_sync_state(sync_dir)
        merged, conflicts = merge_records(local, remote, base)
        for record in merged.values():
            save_record(connection, record)
        connection.commit()
        write_remote(sync_dir, merged)
        write_sync_state(sync_dir, merged)

    if args.git:
        git_call(sync_dir, "add", "commands", ".gcmd-state.json")
        status = git_call(sync_dir, "status", "--porcelain", check=True)
        if status.stdout.strip():
            git_call(sync_dir, "commit", "-m", "Sync gcmd commands")
            push = git_call(sync_dir, "push", check=False)
            if push.returncode != 0:
                print(push.stderr.strip() or "git push failed", file=sys.stderr)
                return 1

    message = f"synced {len(merged)} commands"
    if conflicts:
        message += f"; created {len(conflicts)} conflict cop{'y' if len(conflicts) == 1 else 'ies'}"
    print(message)
    return 0


def init_sync(args: argparse.Namespace) -> int:
    sync_dir = Path(args.directory).expanduser().resolve()
    sync_dir.mkdir(parents=True, exist_ok=True)
    sync_commands_dir(sync_dir).mkdir(parents=True, exist_ok=True)
    if args.git and not (sync_dir / ".git").exists():
        result = subprocess.run(["git", "-C", str(sync_dir), "init"], text=True)
        if result.returncode != 0:
            return result.returncode
    value = config()
    value["sync_dir"] = str(sync_dir)
    write_config(value)
    print(f"sync directory: {sync_dir}")
    if args.git:
        print("Git repository initialized. Add a private remote before using `gcmd sync --git`.")
    return 0


def show_path(_: argparse.Namespace) -> int:
    print(data_dir())
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="gcmd", description="A local-first command library.")
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    save = subparsers.add_parser("save", help="Save a command.")
    save.add_argument("command", nargs="?", help="Command text.")
    save.add_argument("--stdin", action="store_true", help="Read command text from stdin.")
    save.add_argument("--title")
    save.add_argument("--shell")
    save.add_argument("--cwd")
    save.add_argument("--tags", help="Comma-separated tags.")
    save.set_defaults(handler=add_command)

    listing = subparsers.add_parser("list", aliases=["ls"], help="List saved commands.")
    listing.add_argument("query", nargs="?")
    listing.add_argument("--json", action="store_true")
    listing.add_argument("--all", action="store_true", help="Include deleted records.")
    listing.set_defaults(handler=list_commands)

    pick = subparsers.add_parser("pick", help="Search and print one command.")
    pick.add_argument("--query")
    pick.add_argument("--shell")
    pick.add_argument("--cwd")
    pick.set_defaults(handler=pick_command)

    delete = subparsers.add_parser("delete", help="Soft-delete a command.")
    delete.add_argument("id")
    delete.set_defaults(handler=delete_command)

    sync = subparsers.add_parser("sync", help="Synchronize with a directory or Git repository.")
    sync_subparsers = sync.add_subparsers(dest="sync_action")
    sync_init = sync_subparsers.add_parser("init", help="Configure a sync directory.")
    sync_init.add_argument("directory")
    sync_init.add_argument("--git", action="store_true", help="Initialize Git in the directory.")
    sync_init.set_defaults(handler=init_sync)
    sync.add_argument("--directory", "-d")
    sync.add_argument("--git", action="store_true", help="Pull, reconcile, commit, and push.")
    sync.set_defaults(handler=sync_repository)

    path = subparsers.add_parser("path", help="Print local data directory.")
    path.set_defaults(handler=show_path)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.subcommand == "sync" and args.sync_action:
        return args.handler(args)
    if args.subcommand == "sync" and not args.sync_action:
        return args.handler(args)
    return args.handler(args)


if __name__ == "__main__":
    raise SystemExit(main())
