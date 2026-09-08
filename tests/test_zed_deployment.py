import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
SHARED_SEED = REPO_ROOT / "apps/zed/settings.json"
CEKAT_OVERLAY = REPO_ROOT / "apps/zed/cekat-overlay.json"


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

    def test_cekat_activation_seeds_the_work_overlay(self) -> None:
        snippet = self.activation("zaki@cekat", "seedCekatZed")

        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            live = home / ".config/zed/settings.json"

            self.run_activation(snippet, home)

            settings = json.loads(live.read_text())
            model = settings["agent_servers"]["pi-acp"]["default_config_options"]["model"]
            self.assertEqual(model, "litellm/azure_ai/gpt-5.6-luna")
            self.assertNotIn("agent_servers", json.loads(SHARED_SEED.read_text()))
            self.assertEqual(stat.S_IMODE(live.stat().st_mode), 0o644)

    def test_deploy_uses_the_selected_profile_seed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)

            self.run_make("zed-deploy", home, "zaki")
            personal = json.loads((home / ".config/zed/settings.json").read_text())
            self.assertNotIn("agent_servers", personal)

            self.run_make("zed-deploy", home, "zaki@cekat")
            cekat = json.loads((home / ".config/zed/settings.json").read_text())
            self.assertEqual(
                cekat["agent_servers"]["pi-acp"]["default_config_options"]["model"],
                "litellm/azure_ai/gpt-5.6-luna",
            )

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
            self.assertEqual(
                (checkout / "apps/zed/cekat-overlay.json").read_bytes(),
                CEKAT_OVERLAY.read_bytes(),
            )

    def test_non_cekat_harvest_rejects_the_work_subtree(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
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
            before_overlay = (checkout / "apps/zed/cekat-overlay.json").read_bytes()

            result = self.run_make("zed-harvest", home, "zaki", checkout, check=False)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("PROFILE=zaki@cekat", result.stderr)
            self.assertEqual((checkout / "apps/zed/settings.json").read_bytes(), before_shared)
            self.assertEqual((checkout / "apps/zed/cekat-overlay.json").read_bytes(), before_overlay)

    def test_cekat_harvest_keeps_the_work_subtree_out_of_the_shared_seed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
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
                        "agent_servers": {
                            "pi-acp": {
                                "default_config_options": {"model": "work/model"},
                                "type": "registry",
                            }
                        },
                    }
                )
            )

            self.run_make("zed-harvest", home, "zaki@cekat", checkout)

            shared = json.loads((checkout / "apps/zed/settings.json").read_text())
            overlay = json.loads((checkout / "apps/zed/cekat-overlay.json").read_text())
            self.assertEqual(shared, {"ui_font_size": 18})
            self.assertEqual(
                overlay,
                {
                    "agent_servers": {
                        "pi-acp": {
                            "default_config_options": {"model": "work/model"},
                            "type": "registry",
                        }
                    }
                },
            )

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
            before_overlay = (checkout / "apps/zed/cekat-overlay.json").read_bytes()

            result = self.run_make("zed-harvest", home, "zaki@cekat", checkout, check=False)

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((checkout / "apps/zed/settings.json").read_bytes(), before_shared)
            self.assertEqual((checkout / "apps/zed/cekat-overlay.json").read_bytes(), before_overlay)

    def copy_zed_fixture(self, checkout: Path) -> None:
        (checkout / "apps/zed").mkdir(parents=True)
        (checkout / "apps/zed/settings.json").write_bytes(SHARED_SEED.read_bytes())
        (checkout / "apps/zed/cekat-overlay.json").write_bytes(CEKAT_OVERLAY.read_bytes())
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
