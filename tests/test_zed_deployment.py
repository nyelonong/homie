import json
import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
SHARED_SEED = REPO_ROOT / "apps/zed/settings.json"


class ZedDeploymentTest(unittest.TestCase):
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

    def test_shared_activation_seeds_a_writable_regular_file(self) -> None:
        snippet = self.activation("zaki", "seedZed")

        for initial_state in ("missing", "symlink"):
            with self.subTest(initial_state=initial_state), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                live = home / ".config/zed/settings.json"
                if initial_state == "symlink":
                    live.parent.mkdir(parents=True)
                    live.symlink_to(SHARED_SEED)

                self.run_activation(snippet, home)

                self.assertFalse(live.is_symlink())
                self.assertEqual(stat.S_IMODE(live.stat().st_mode), 0o644)
                self.assertEqual(json.loads(live.read_text()), json.loads(SHARED_SEED.read_text()))

    def test_activation_preserves_existing_app_settings(self) -> None:
        snippet = self.activation("zaki", "seedZed")

        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            live = home / ".config/zed/settings.json"
            live.parent.mkdir(parents=True)
            live.write_text('{"changed_in_zed": true}\n')

            self.run_activation(snippet, home)

            self.assertEqual(live.read_text(), '{"changed_in_zed": true}\n')

    def test_cekat_activation_seeds_the_shared_settings(self) -> None:
        snippet = self.activation("zaki@cekat", "seedZed")

        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            live = home / ".config/zed/settings.json"

            self.run_activation(snippet, home)

            self.assertEqual(json.loads(live.read_text()), json.loads(SHARED_SEED.read_text()))
            self.assertFalse(live.is_symlink())
            self.assertEqual(stat.S_IMODE(live.stat().st_mode), 0o644)

    def test_deploy_uses_the_shared_seed_for_every_profile(self) -> None:
        for profile in ("zaki", "zaki@cekat", "zaki@windows"):
            with self.subTest(profile=profile), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)

                self.run_make("zed-deploy", home, profile)

                live = home / ".config/zed/settings.json"
                self.assertEqual(json.loads(live.read_text()), json.loads(SHARED_SEED.read_text()))
                self.assertEqual(stat.S_IMODE(live.stat().st_mode), 0o644)

    def test_shared_harvest_updates_the_common_seed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            checkout = root / "checkout"
            home = root / "home"
            self.copy_zed_fixture(checkout)
            live = home / ".config/zed/settings.json"
            live.parent.mkdir(parents=True)
            live.write_text('{"ui_font_size": 18}\n')

            self.run_make("zed-harvest", home, "zaki", checkout)

            self.assertEqual(
                json.loads((checkout / "apps/zed/settings.json").read_text()),
                {"ui_font_size": 18},
            )

    def test_harvest_rejects_the_work_subtree_for_every_profile(self) -> None:
        for profile in ("zaki", "zaki@cekat", "zaki@windows"):
            with self.subTest(profile=profile), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                checkout = root / "checkout"
                home = root / "home"
                self.copy_zed_fixture(checkout)
                live = home / ".config/zed/settings.json"
                live.parent.mkdir(parents=True)
                live.write_text(
                    json.dumps(
                        {
                            "ui_font_size": 18,
                            "agent_servers": {"pi-acp": {"default_config_options": {}}},
                        }
                    )
                )
                before_shared = (checkout / "apps/zed/settings.json").read_bytes()

                result = self.run_make("zed-harvest", home, profile, checkout, check=False)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("remove it before harvesting", result.stderr)
                self.assertEqual((checkout / "apps/zed/settings.json").read_bytes(), before_shared)
                self.assertFalse((checkout / "apps/zed/cekat-overlay.json").exists())

    def test_harvest_preserves_other_agent_settings_for_every_profile(self) -> None:
        settings = {
            "ui_font_size": 18,
            "agent_servers": {"other-agent": {"type": "registry"}},
        }
        for profile in ("zaki", "zaki@cekat", "zaki@windows"):
            with self.subTest(profile=profile), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                checkout = root / "checkout"
                home = root / "home"
                self.copy_zed_fixture(checkout)
                live = home / ".config/zed/settings.json"
                live.parent.mkdir(parents=True)
                live.write_text(json.dumps(settings))

                self.run_make("zed-harvest", home, profile, checkout)

                self.assertEqual(
                    json.loads((checkout / "apps/zed/settings.json").read_text()),
                    settings,
                )
                self.assertFalse((checkout / "apps/zed/cekat-overlay.json").exists())

    def test_invalid_live_json_does_not_change_seeds(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            checkout = root / "checkout"
            home = root / "home"
            self.copy_zed_fixture(checkout)
            live = home / ".config/zed/settings.json"
            live.parent.mkdir(parents=True)
            live.write_text("not json\n")
            before_shared = (checkout / "apps/zed/settings.json").read_bytes()

            result = self.run_make("zed-harvest", home, "zaki@cekat", checkout, check=False)

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((checkout / "apps/zed/settings.json").read_bytes(), before_shared)

    def test_harvest_rejects_multiple_json_documents_without_changing_seed(self) -> None:
        for profile in ("zaki", "zaki@cekat", "zaki@windows"):
            with self.subTest(profile=profile), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                checkout = root / "checkout"
                home = root / "home"
                self.copy_zed_fixture(checkout)
                live = home / ".config/zed/settings.json"
                live.parent.mkdir(parents=True)
                live.write_text('{"agent_servers":{"pi-acp":{"type":"registry"}}}\n{}\n')
                shared = checkout / "apps/zed/settings.json"
                before = shared.read_bytes()

                result = self.run_make("zed-harvest", home, profile, checkout, check=False)

                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(shared.read_bytes(), before)

    def test_harvest_promotes_only_the_validated_snapshot(self) -> None:
        real_jq = shutil.which("jq")
        self.assertIsNotNone(real_jq)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            checkout = root / "checkout"
            home = root / "home"
            self.copy_zed_fixture(checkout)
            live = home / ".config/zed/settings.json"
            live.parent.mkdir(parents=True)
            settings = {"ui_font_size": 18}
            live.write_text(json.dumps(settings))
            work_settings = {"agent_servers": {"pi-acp": {"type": "registry"}}}
            bin_directory = root / "bin"
            bin_directory.mkdir()
            wrapper = bin_directory / "jq"
            wrapper.write_text(
                "#!/usr/bin/env python3\n"
                "import json, subprocess, sys\n"
                "from pathlib import Path\n"
                f"result = subprocess.run([{real_jq!r}, *sys.argv[1:]])\n"
                "if any('has(\"pi-acp\")' in argument for argument in sys.argv[1:]):\n"
                "    live = Path(sys.argv[-1])\n"
                "    replacement = live.with_suffix('.replacement')\n"
                f"    replacement.write_text(json.dumps({work_settings!r}))\n"
                "    replacement.replace(live)\n"
                "sys.exit(result.returncode)\n"
            )
            wrapper.chmod(0o755)

            subprocess.run(
                ["make", "zed-harvest", "PROFILE=zaki@cekat"],
                cwd=checkout,
                env={**os.environ, "HOME": str(home), "PATH": f"{bin_directory}:{os.environ['PATH']}"},
                check=True,
                capture_output=True,
                text=True,
            )

            self.assertEqual(json.loads(live.read_text()), work_settings)
            self.assertEqual(
                json.loads((checkout / "apps/zed/settings.json").read_text()),
                settings,
            )

    def copy_zed_fixture(self, checkout: Path) -> None:
        (checkout / "apps/zed").mkdir(parents=True)
        (checkout / "apps/zed/settings.json").write_bytes(SHARED_SEED.read_bytes())
        (checkout / "Makefile").write_bytes((REPO_ROOT / "Makefile").read_bytes())

    def run_make(
        self,
        target: str,
        home: Path,
        profile: str,
        cwd: Path = REPO_ROOT,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["make", target, f"PROFILE={profile}"],
            cwd=cwd,
            env={**os.environ, "HOME": str(home)},
            check=check,
            capture_output=True,
            text=True,
        )


if __name__ == "__main__":
    unittest.main()
