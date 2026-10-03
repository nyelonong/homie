import importlib.util
import stat
import tempfile
import tomllib
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/herdr-config.py"
SPEC = importlib.util.spec_from_file_location("herdr_config", SCRIPT)
CONFIG = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONFIG)


class HerdrConfigTest(unittest.TestCase):
    def test_invalid_toml_preserves_destination(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.toml"
            destination = root / "destination.toml"
            source.write_text("[broken\n")
            destination.write_bytes(b"enabled = false\n")
            before = set(root.iterdir())

            with self.assertRaises(tomllib.TOMLDecodeError):
                CONFIG.transfer_config(source, destination)

            self.assertEqual(destination.read_bytes(), b"enabled = false\n")
            self.assertEqual(set(root.iterdir()), before)

    def test_invalid_utf8_preserves_destination(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.toml"
            destination = Path(directory) / "destination.toml"
            source.write_bytes(b"\xff")
            destination.write_bytes(b"enabled = false\n")

            with self.assertRaises(UnicodeDecodeError):
                CONFIG.transfer_config(source, destination)

            self.assertEqual(destination.read_bytes(), b"enabled = false\n")

    def test_missing_source_does_not_create_destination(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            destination = root / "nested/config.toml"

            with self.assertRaises(FileNotFoundError):
                CONFIG.transfer_config(root / "missing.toml", destination)

            self.assertFalse(destination.parent.exists())

    def test_valid_copy_atomically_replaces_destination(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.toml"
            destination = Path(directory) / "destination.toml"
            content = b"# preserved formatting\nenabled = true\n"
            source.write_bytes(content)
            destination.write_bytes(b"enabled = false\n")

            with destination.open("rb") as original:
                self.assertTrue(CONFIG.transfer_config(source, destination))
                self.assertEqual(original.read(), b"enabled = false\n")

            self.assertEqual(destination.read_bytes(), content)
            self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o644)

    def test_unchanged_writable_destination_is_preserved(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.toml"
            destination = Path(directory) / "destination.toml"
            content = b"enabled = true\n"
            source.write_bytes(content)
            destination.write_bytes(content)
            destination.chmod(0o644)

            self.assertFalse(CONFIG.transfer_config(source, destination))

            self.assertEqual(destination.read_bytes(), content)

    def test_identical_readonly_destination_becomes_writable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.toml"
            destination = Path(directory) / "destination.toml"
            content = b"enabled = true\n"
            source.write_bytes(content)
            destination.write_bytes(content)
            destination.chmod(0o444)

            self.assertTrue(CONFIG.transfer_config(source, destination))

            self.assertEqual(destination.read_bytes(), content)
            self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o644)

    def test_identical_symlink_is_replaced_without_changing_its_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.toml"
            destination = root / "destination.toml"
            foreign = root / "foreign.toml"
            content = b"enabled = true\n"
            source.write_bytes(content)
            foreign.write_bytes(content)
            foreign.chmod(0o644)
            destination.symlink_to(foreign)

            self.assertTrue(CONFIG.transfer_config(source, destination))

            self.assertFalse(destination.is_symlink())
            self.assertEqual(destination.read_bytes(), content)
            self.assertEqual(foreign.read_bytes(), content)

    def test_source_change_after_validation_does_not_change_copied_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.toml"
            destination = Path(directory) / "destination.toml"
            content = b"enabled = true\n"
            source.write_bytes(content)
            parse = tomllib.loads

            def parse_then_change_source(text):
                result = parse(text)
                source.write_text("[broken\n")
                return result

            with patch.object(CONFIG.tomllib, "loads", side_effect=parse_then_change_source):
                self.assertTrue(CONFIG.transfer_config(source, destination))

            self.assertEqual(destination.read_bytes(), content)
            self.assertEqual(source.read_text(), "[broken\n")

    def test_replace_failure_preserves_destination_and_cleans_temporary_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.toml"
            destination = root / "destination.toml"
            source.write_bytes(b"enabled = true\n")
            destination.write_bytes(b"enabled = false\n")
            before = set(root.iterdir())

            with patch.object(CONFIG.os, "replace", side_effect=OSError("replacement failed")):
                with self.assertRaises(OSError):
                    CONFIG.transfer_config(source, destination)

            self.assertEqual(destination.read_bytes(), b"enabled = false\n")
            self.assertEqual(set(root.iterdir()), before)


if __name__ == "__main__":
    unittest.main()
