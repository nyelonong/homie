from pathlib import Path
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import doctor  # noqa: E402


HEALTHY_OUTPUT = {
    ("omniwmctl", "ping"): "pong\n",
    ("launchctl", "list", doctor.SKHD_LABEL): '{\n\t"Label" = "x";\n\t"PID" = 98225;\n};\n',
    ("ioreg", "-l", "-w0"): '"IOConsoleLocked" = No\n',
    ("hidutil", "property", "--get", "UserKeyMapping"): (
        "(\n        {\n        HIDKeyboardModifierMappingDst = 30064771181;\n"
        "        HIDKeyboardModifierMappingSrc = 30064771129;\n    }\n)\n"
    ),
}


class DoctorTest(unittest.TestCase):
    def setUp(self) -> None:
        self._directory = tempfile.TemporaryDirectory()
        self.addCleanup(self._directory.cleanup)
        root = Path(self._directory.name)
        self.home, self.repo = root / "home", root / "repo"
        omniwm = '[general]\nsystemHyperTrigger = "Caps Lock"\n'
        for path, text in {
            self.home / ".config/omniwm/settings.toml": omniwm,
            self.repo / "apps/omniwm/settings.toml": omniwm,
            self.home / ".config/ghostty/config": "font-size = 15\n",
            self.repo / "apps/ghostty/config": "font-size = 15\n",
            self.home / ".skhdrc": "cmd + alt - t : x\n",
            self.repo / ".skhdrc": "cmd + alt - t : x\n",
        }.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)

    def diagnose(self, **overrides: str) -> dict[str, str]:
        output = {**HEALTHY_OUTPUT, **{tuple(key.split("|")): value for key, value in overrides.items()}}
        results = doctor.check_stack(self.home, self.repo, runner=lambda *command: output.get(command, ""))
        return {name: status for status, name, _ in results}

    def test_healthy_stack_reports_no_problems(self) -> None:
        self.assertEqual(set(self.diagnose().values()), {"ok"})

    def test_stuck_secure_input_fails_and_names_the_holder(self) -> None:
        stuck = '"kCGSSessionSecureInputPID"=171\n'
        self.assertEqual(self.diagnose(**{"ioreg|-l|-w0": stuck})["secure-input"], "fail")

    def test_missing_f18_remap_fails_only_when_caps_lock_hyper_is_enabled(self) -> None:
        empty = "(\n)\n"
        self.assertEqual(self.diagnose(**{"hidutil|property|--get|UserKeyMapping": empty})["caps-remap"], "fail")

        (self.home / ".config/omniwm/settings.toml").write_text('[general]\nsystemHyperTrigger = "None"\n')
        self.assertEqual(self.diagnose(**{"hidutil|property|--get|UserKeyMapping": empty})["caps-remap"], "ok")

    def test_stopped_services_fail(self) -> None:
        statuses = self.diagnose(**{"omniwmctl|ping": "", f"launchctl|list|{doctor.SKHD_LABEL}": ""})
        self.assertEqual((statuses["omniwm"], statuses["skhd"]), ("fail", "fail"))

    def test_drift_between_seed_and_live_file_warns(self) -> None:
        (self.home / ".config/ghostty/config").write_text("font-size = 18\n")
        statuses = self.diagnose()
        self.assertEqual(statuses["ghostty-seed"], "warn")
        self.assertEqual(statuses["omniwm-seed"], "ok")


if __name__ == "__main__":
    unittest.main()
