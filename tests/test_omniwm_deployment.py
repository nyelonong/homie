from pathlib import Path
import os
import stat
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parent.parent
SEED = REPO_ROOT / "apps/omniwm/settings.toml"


class OmniWMDeploymentTest(unittest.TestCase):
    def test_activation_seeds_a_writable_regular_file(self) -> None:
        snippet = subprocess.run(
            [
                "nix",
                "eval",
                "--raw",
                '.#homeConfigurations."zaki".config.home.activation.seedOmniWM.data',
            ],
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout

        for initial_state in ("missing", "symlink"):
            with self.subTest(initial_state=initial_state), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                live = home / ".config/omniwm/settings.toml"
                if initial_state == "symlink":
                    live.parent.mkdir(parents=True)
                    live.symlink_to(SEED)

                subprocess.run(
                    ["bash", "-c", snippet],
                    cwd=REPO_ROOT,
                    env={**os.environ, "HOME": str(home)},
                    check=True,
                )

                self.assertFalse(live.is_symlink())
                self.assertEqual(stat.S_IMODE(live.stat().st_mode), 0o644)
                self.assertEqual(live.read_bytes(), SEED.read_bytes())

    def test_deploy_preserves_the_seed_across_app_shutdown(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            live = home / ".config/omniwm/settings.toml"
            live.parent.mkdir(parents=True)
            live.write_text("current app state\n")
            events = root / "events"
            fake_bin = root / "bin"
            fake_bin.mkdir()
            self.write_executable(
                fake_bin / "pkill",
                '#!/bin/sh\nprintf "stop\\n" >> "$OMNIWM_TEST_EVENTS"\nprintf "old app state\\n" > "$HOME/.config/omniwm/settings.toml"\n',
            )
            self.write_executable(fake_bin / "pgrep", "#!/bin/sh\nexit 1\n")
            self.write_executable(
                fake_bin / "open",
                '#!/bin/sh\nprintf "open\\n" >> "$OMNIWM_TEST_EVENTS"\n',
            )

            subprocess.run(
                ["make", "omniwm-deploy"],
                cwd=REPO_ROOT,
                env={
                    **os.environ,
                    "HOME": str(home),
                    "OMNIWM_TEST_EVENTS": str(events),
                    "PATH": f"{fake_bin}:{os.environ['PATH']}",
                },
                check=True,
            )

            self.assertEqual(live.read_bytes(), SEED.read_bytes())
            self.assertEqual(stat.S_IMODE(live.stat().st_mode), 0o644)
            self.assertEqual(events.read_text(), "stop\nopen\n")

    def write_executable(self, path: Path, content: str) -> None:
        path.write_text(content)
        path.chmod(0o755)


if __name__ == "__main__":
    unittest.main()
