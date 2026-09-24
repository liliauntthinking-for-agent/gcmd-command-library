import json
import os
import tempfile
import unittest
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import gcmd


class GcmdTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        os.environ["GCMD_HOME"] = self.temp_dir.name

    def tearDown(self):
        os.environ.pop("GCMD_HOME", None)
        self.temp_dir.cleanup()

    def test_save_and_search(self):
        args = gcmd.build_parser().parse_args(
            ["save", "--title", "Git status", "--tags", "git,daily", "git status -sb"]
        )
        self.assertEqual(gcmd.add_command(args), 0)
        with gcmd.database() as connection:
            records = gcmd.search_records(connection, "daily")
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["command"], "git status -sb")

    def test_sync_round_trip(self):
        args = gcmd.build_parser().parse_args(["save", "echo hello"])
        self.assertEqual(gcmd.add_command(args), 0)
        sync_dir = Path(self.temp_dir.name) / "sync"
        init_args = gcmd.build_parser().parse_args(["sync", "init", str(sync_dir)])
        self.assertEqual(gcmd.init_sync(init_args), 0)
        sync_args = gcmd.build_parser().parse_args(["sync"])
        self.assertEqual(gcmd.sync_repository(sync_args), 0)

        with gcmd.database() as connection:
            connection.execute("DELETE FROM commands")
            connection.commit()
        self.assertEqual(gcmd.sync_repository(sync_args), 0)
        connection = gcmd.connect()
        try:
            records = gcmd.all_records(connection)
        finally:
            connection.close()
        self.assertEqual(len(records), 1)
        remote_file = next((sync_dir / "commands").glob("*.json"))
        self.assertEqual(json.loads(remote_file.read_text())["command"], "echo hello")


if __name__ == "__main__":
    unittest.main()
