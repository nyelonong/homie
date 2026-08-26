import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ProfileBoundaryTest(unittest.TestCase):
    def config_has(self, profile: str, path: str, name: str) -> bool:
        target = f'.#homeConfigurations."{profile}".config.{path}'
        result = subprocess.run(
            [
                "nix",
                "eval",
                "--json",
                target,
                "--apply",
                f'value: builtins.hasAttr "{name}" value',
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(result.stdout)

    def config_text(self, profile: str, path: str) -> str:
        target = f'.#homeConfigurations."{profile}".config.{path}'
        return subprocess.run(
            ["nix", "eval", "--raw", target],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout

    def test_desktop_lifecycle_belongs_only_to_personal_profile(self) -> None:
        boundaries = (
            ("launchd.agents", "skhd"),
            ("home.activation", "seedOmniWM"),
            ("home.activation", "reloadSkhd"),
            ("home.file", ".skhdrc"),
        )

        for path, name in boundaries:
            with self.subTest(profile="zaki", path=path, name=name):
                self.assertTrue(self.config_has("zaki", path, name))

        for profile in ("zaki@cekat", "zaki@windows"):
            for path, name in boundaries:
                with self.subTest(profile=profile, path=path, name=name):
                    self.assertFalse(self.config_has(profile, path, name))

    def test_shell_has_no_cmux_pi_wrappers(self) -> None:
        for profile in ("zaki", "zaki@cekat", "zaki@windows"):
            with self.subTest(profile=profile):
                init = self.config_text(profile, "programs.zsh.initContent")
                self.assertNotIn("function pi-cekat()", init)
                self.assertNotIn("function pi-codex()", init)
                self.assertNotIn("function pi-opencode()", init)
                self.assertNotIn("function pi-openrouter()", init)
                self.assertNotIn("CMUX_BUNDLED_CLI_PATH", init)

    def test_cekat_zed_model_belongs_only_to_work_profile(self) -> None:
        for profile in ("zaki", "zaki@windows"):
            with self.subTest(profile=profile):
                settings = json.loads(
                    self.config_text(
                        profile,
                        'home.file.".config/zed/settings.json".text',
                    )
                )
                self.assertNotIn("litellm/azure_ai/gpt-5.6-terra", json.dumps(settings))

        cekat_settings = json.loads(
            self.config_text(
                "zaki@cekat",
                'home.file.".config/zed/settings.json".text',
            )
        )
        model = cekat_settings["agent_servers"]["pi-acp"]["default_config_options"]["model"]
        self.assertEqual(model, "litellm/azure_ai/gpt-5.6-terra")


if __name__ == "__main__":
    unittest.main()
