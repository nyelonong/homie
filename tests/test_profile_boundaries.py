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


if __name__ == "__main__":
    unittest.main()
