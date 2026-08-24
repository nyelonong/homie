import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = ROOT / "bootstrap.sh"


class BootstrapTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.bin = self.root / "bin"
        self.log = self.root / "commands.log"
        self.home.mkdir()
        self.bin.mkdir()
        key = self.home / ".ssh/id_ed25519"
        key.parent.mkdir()
        key.touch()

        self.write_executable(
            "uname",
            """#!/bin/sh
case "$1" in
  -s) printf '%s\n' "${FAKE_OS:-Darwin}" ;;
  -r) printf '%s\n' "${FAKE_KERNEL_RELEASE:-24.0.0}" ;;
  *) exit 2 ;;
esac
""",
        )
        self.write_executable(
            "nix",
            """#!/bin/sh
printf 'nix' >> "$COMMAND_LOG"
for argument in "$@"; do printf '\t%s' "$argument" >> "$COMMAND_LOG"; done
printf '\n' >> "$COMMAND_LOG"
""",
        )
        self.write_executable(
            "git",
            """#!/bin/sh
printf 'git' >> "$COMMAND_LOG"
for argument in "$@"; do printf '\t%s' "$argument" >> "$COMMAND_LOG"; done
printf '\n' >> "$COMMAND_LOG"
case "$*" in
  *"remote get-url origin"*) printf '%s\n' "${FAKE_REMOTE:-https://github.com/nyelonong/homie.git}" ;;
  *"status --porcelain"*) printf '%s' "${FAKE_STATUS:-}" ;;
  *"symbolic-ref --short HEAD"*) printf '%s\n' "${FAKE_BRANCH:-main}" ;;
esac
""",
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_executable(self, name: str, content: str) -> None:
        path = self.bin / name
        path.write_text(content)
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def existing_repo(self) -> Path:
        repo = self.home / "homie"
        (repo / ".git").mkdir(parents=True)
        (repo / "flake.nix").touch()
        return repo

    def run_bootstrap(self, **overrides: str) -> subprocess.CompletedProcess[str]:
        environment = {
            **os.environ,
            "HOME": str(self.home),
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "COMMAND_LOG": str(self.log),
            **overrides,
        }
        return subprocess.run(
            ["/bin/sh", str(BOOTSTRAP)],
            cwd=ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )

    def commands(self) -> str:
        return self.log.read_text() if self.log.exists() else ""

    def test_rejects_non_wsl_linux(self) -> None:
        result = self.run_bootstrap(FAKE_OS="Linux", FAKE_KERNEL_RELEASE="6.12.0-generic")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("WSL", result.stderr)
        self.assertNotIn("home-manager", self.commands())

    def test_rejects_profile_incompatible_with_platform_before_checkout(self) -> None:
        result = self.run_bootstrap(PROFILE="zaki@windows")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not supported on Darwin", result.stderr)
        self.assertNotIn("\tclone\t", self.commands())

    def test_rejects_existing_non_repository_directory(self) -> None:
        (self.home / "homie").mkdir()

        result = self.run_bootstrap()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not the homie Git repository", result.stderr)
        self.assertNotIn("home-manager", self.commands())

    def test_rejects_unexpected_remote(self) -> None:
        self.existing_repo()

        result = self.run_bootstrap(FAKE_REMOTE="https://example.com/not-homie.git")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unexpected origin", result.stderr)
        self.assertNotIn("home-manager", self.commands())

    def test_rejects_dirty_checkout_before_fetch(self) -> None:
        self.existing_repo()

        result = self.run_bootstrap(FAKE_STATUS=" M home.nix")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("uncommitted changes", result.stderr)
        self.assertNotIn("fetch", self.commands())

    def test_updates_clean_checkout_without_rewriting_history(self) -> None:
        self.existing_repo()

        result = self.run_bootstrap()

        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        self.assertIn("git\t-C\t" + str(self.home / "homie") + "\tfetch\t--prune\torigin", commands)
        self.assertIn(
            "git\t-C\t" + str(self.home / "homie") + "\tmerge\t--ff-only\torigin/main",
            commands,
        )
        self.assertNotIn("reset", commands)

    def test_uses_repository_locked_apps(self) -> None:
        repo = self.existing_repo()

        result = self.run_bootstrap()

        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        self.assertIn(f"nix\trun\t{repo}#home-manager\t--\tswitch\t--flake\t{repo}#zaki", commands)
        self.assertIn(f"nix\trun\t{repo}#mise\t--\tinstall\t--yes", commands)
        self.assertNotIn("github:nix-community/home-manager", commands)
        self.assertNotIn("nixpkgs#mise", commands)

    def test_wsl_uses_windows_profile(self) -> None:
        repo = self.existing_repo()

        result = self.run_bootstrap(
            FAKE_OS="Linux",
            FAKE_KERNEL_RELEASE="6.6.87.2-microsoft-standard-WSL2",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"--flake\t{repo}#zaki@windows", self.commands())


if __name__ == "__main__":
    unittest.main()
