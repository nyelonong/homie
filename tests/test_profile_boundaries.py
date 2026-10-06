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

    def package_names(self, profile: str) -> set[str]:
        target = f'.#homeConfigurations."{profile}".config.home.packages'
        result = subprocess.run(
            ["nix", "eval", "--json", target, "--apply", "ps: map (p: p.pname or p.name) ps"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        return set(json.loads(result.stdout))

    def test_kubernetes_tools_belong_to_personal_and_are_inherited_by_cekat(self) -> None:
        tools = {"kubectl", "kubernetes-helm", "k9s", "opentofu", "mongosh"}

        for profile in ("zaki", "zaki@cekat"):
            with self.subTest(profile=profile):
                self.assertLessEqual(tools, self.package_names(profile))
                self.assertTrue(self.config_has(profile, "programs.zsh.shellAliases", "kgp"))

        with self.subTest(profile="zaki@windows"):
            self.assertFalse(tools & self.package_names("zaki@windows"))
            self.assertFalse(self.config_has("zaki@windows", "programs.zsh.shellAliases", "kgp"))

    def test_org_go_variables_belong_only_to_cekat(self) -> None:
        for profile, expected in (("zaki@cekat", True), ("zaki", False), ("zaki@windows", False)):
            for name in ("GOPRIVATE", "GONOSUMDB"):
                with self.subTest(profile=profile, name=name):
                    self.assertEqual(
                        self.config_has(profile, "home.sessionVariables", name), expected
                    )

    def test_skhd_belongs_to_darwin_profiles(self) -> None:
        boundaries = (
            ("launchd.agents", "skhd"),
            ("home.activation", "reloadSkhd"),
            ("home.file", ".skhdrc"),
        )

        for profile in ("zaki", "zaki@cekat"):
            for path, name in boundaries:
                with self.subTest(profile=profile, path=path, name=name):
                    self.assertTrue(self.config_has(profile, path, name))

        for path, name in boundaries:
            with self.subTest(profile="zaki@windows", path=path, name=name):
                self.assertFalse(self.config_has("zaki@windows", path, name))

    def test_ghostty_seed_belongs_to_darwin_profiles(self) -> None:
        for profile in ("zaki", "zaki@cekat"):
            with self.subTest(profile=profile):
                self.assertTrue(self.config_has(profile, "home.activation", "seedGhostty"))
                self.assertFalse(
                    self.config_has(profile, "home.file", ".config/ghostty/config")
                )

        with self.subTest(profile="zaki@windows"):
            self.assertFalse(self.config_has("zaki@windows", "home.activation", "seedGhostty"))
            self.assertFalse(
                self.config_has("zaki@windows", "home.file", ".config/ghostty/config")
            )

    def test_omniwm_lifecycle_belongs_to_darwin_profiles(self) -> None:
        boundaries = (
            ("home.activation", "seedOmniWM"),
        )

        for profile in ("zaki", "zaki@cekat"):
            for path, name in boundaries:
                with self.subTest(profile=profile, path=path, name=name):
                    self.assertTrue(self.config_has(profile, path, name))

        for path, name in boundaries:
            with self.subTest(profile="zaki@windows", path=path, name=name):
                self.assertFalse(self.config_has("zaki@windows", path, name))

    def test_shell_has_no_cmux_pi_wrappers(self) -> None:
        for profile in ("zaki", "zaki@cekat", "zaki@windows"):
            with self.subTest(profile=profile):
                init = self.config_text(profile, "programs.zsh.initContent")
                self.assertNotIn("function pi-cekat()", init)
                self.assertNotIn("function pi-codex()", init)
                self.assertNotIn("function pi-opencode()", init)
                self.assertNotIn("function pi-openrouter()", init)
                self.assertNotIn("CMUX_BUNDLED_CLI_PATH", init)

    def test_zed_settings_are_app_owned_and_use_the_shared_seed(self) -> None:
        for profile in ("zaki", "zaki@cekat", "zaki@windows"):
            with self.subTest(profile=profile):
                self.assertTrue(self.config_has(profile, "home.activation", "seedZed"))
                self.assertFalse(
                    self.config_has(
                        profile,
                        "home.file",
                        ".config/zed/settings.json",
                    )
                )

        for profile in ("zaki", "zaki@cekat", "zaki@windows"):
            with self.subTest(profile=profile):
                self.assertFalse(
                    self.config_has(profile, "home.activation", "seedCekatZed")
                )


if __name__ == "__main__":
    unittest.main()
