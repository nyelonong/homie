import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
SEED = REPO_ROOT / "apps/ghostty/config"


class GhosttyDeploymentTest(unittest.TestCase):
    def activation(self, profile: str, name: str) -> str:
        return subprocess.run(
            [
                "nix",
                "eval",
                "--raw",
                f'.#homeConfigurations."{profile}".config.home.activation.{name}.data',
            ],
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout

    def run_activation(self, snippet: str, home: Path) -> None:
        subprocess.run(
            ["bash", "-c", snippet],
            cwd=REPO_ROOT,
            env={**os.environ, "HOME": str(home)},
            check=True,
        )

    def run_make(
        self,
        target: str,
        home: Path,
        cwd: Path = REPO_ROOT,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["make", target],
            cwd=cwd,
            env={**os.environ, "HOME": str(home)},
            check=True,
            capture_output=True,
            text=True,
        )

    def test_activation_seeds_a_writable_regular_file(self) -> None:
        snippet = self.activation("zaki", "seedGhostty")

        for initial_state in ("missing", "symlink"):
            with self.subTest(initial_state=initial_state), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                live = home / ".config/ghostty/config"
                if initial_state == "symlink":
                    live.parent.mkdir(parents=True)
                    live.symlink_to(SEED)

                self.run_activation(snippet, home)

                self.assertFalse(live.is_symlink())
                self.assertEqual(stat.S_IMODE(live.stat().st_mode), 0o644)
                self.assertEqual(live.read_bytes(), SEED.read_bytes())

    def test_activation_preserves_live_edits(self) -> None:
        snippet = self.activation("zaki", "seedGhostty")

        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            live = home / ".config/ghostty/config"
            live.parent.mkdir(parents=True)
            live.write_text("font-size = 42\n")

            self.run_activation(snippet, home)

            self.assertEqual(live.read_text(), "font-size = 42\n")

    def test_deploy_pushes_the_seed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            live = home / ".config/ghostty/config"
            live.parent.mkdir(parents=True)
            live.write_text("font-size = 9\n")

            self.run_make("ghostty-deploy", home)

            self.assertEqual(live.read_bytes(), SEED.read_bytes())
            self.assertEqual(stat.S_IMODE(live.stat().st_mode), 0o644)

    def test_harvest_pulls_live_edits_into_the_seed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            checkout = root / "checkout"
            home = root / "home"
            (checkout / "apps/ghostty").mkdir(parents=True)
            (checkout / "apps/ghostty/config").write_bytes(SEED.read_bytes())
            (checkout / "Makefile").write_bytes((REPO_ROOT / "Makefile").read_bytes())
            live = home / ".config/ghostty/config"
            live.parent.mkdir(parents=True)
            live.write_text("font-size = 42\n")

            self.run_make("ghostty-harvest", home, cwd=checkout)

            self.assertEqual(
                (checkout / "apps/ghostty/config").read_text(), "font-size = 42\n"
            )

    def test_harvest_leaves_the_seed_alone_when_there_are_no_changes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            checkout = root / "checkout"
            home = root / "home"
            (checkout / "apps/ghostty").mkdir(parents=True)
            (checkout / "apps/ghostty/config").write_bytes(SEED.read_bytes())
            (checkout / "Makefile").write_bytes((REPO_ROOT / "Makefile").read_bytes())
            live = home / ".config/ghostty/config"
            live.parent.mkdir(parents=True)
            live.write_bytes(SEED.read_bytes())

            result = self.run_make("ghostty-harvest", home, cwd=checkout)

            self.assertIn("no changes", result.stdout)
            self.assertEqual((checkout / "apps/ghostty/config").read_bytes(), SEED.read_bytes())


if __name__ == "__main__":
    unittest.main()