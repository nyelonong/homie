#!/usr/bin/env python3
"""Read-only health check for the macOS keyboard and window-manager stack."""

from pathlib import Path
import os
import re
import subprocess
import sys
import tomllib


REPO_ROOT = Path(__file__).resolve().parent.parent
CAPS_LOCK = 0x700000039
F18 = 0x70000006D
SKHD_LABEL = "org.nix-community.home.skhd"


def run(*command: str) -> str:
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return result.stdout


def secure_input_pid(ioreg_output: str) -> int | None:
    match = re.search(r'"kCGSSessionSecureInputPID"\s*=\s*(\d+)', ioreg_output)
    return int(match.group(1)) if match else None


def caps_lock_remapped_to_f18(hidutil_output: str) -> bool:
    for block in re.findall(r"\{[^}]*\}", hidutil_output):
        source = re.search(r"HIDKeyboardModifierMappingSrc\s*=\s*(\d+)", block)
        destination = re.search(r"HIDKeyboardModifierMappingDst\s*=\s*(\d+)", block)
        if source and destination and (int(source.group(1)), int(destination.group(1))) == (CAPS_LOCK, F18):
            return True
    return False


def wants_caps_lock_hyper(settings_text: str) -> bool:
    general = tomllib.loads(settings_text).get("general", {})
    return general.get("systemHyperTrigger") == "Caps Lock"


def same_file(left: Path, right: Path) -> bool:
    try:
        return left.read_bytes() == right.read_bytes()
    except OSError:
        return False


def check_stack(home: Path, repo: Path, runner=run) -> list[tuple[str, str, str]]:
    results: list[tuple[str, str, str]] = []

    def report(status: str, name: str, detail: str) -> None:
        results.append((status, name, detail))

    if "pong" in runner("omniwmctl", "ping"):
        report("ok", "omniwm", "answers ping")
    else:
        report("fail", "omniwm", "not answering; run: open -a OmniWM")

    if re.search(r'"PID"\s*=\s*\d+', runner("launchctl", "list", SKHD_LABEL)):
        report("ok", "skhd", "running")
    else:
        report("fail", "skhd", f"not running; run: launchctl kickstart -k gui/{os.getuid()}/{SKHD_LABEL}")

    holder = secure_input_pid(runner("ioreg", "-l", "-w0"))
    if holder is None:
        report("ok", "secure-input", "not held")
    else:
        name = runner("ps", "-o", "comm=", "-p", str(holder)).strip() or "unknown process"
        report(
            "fail",
            "secure-input",
            f"held by pid {holder} ({name}); event taps are blocked. Close that app, or log out and back in",
        )

    live_omniwm = home / ".config/omniwm/settings.toml"
    try:
        hyper_wanted = wants_caps_lock_hyper(live_omniwm.read_text())
    except (OSError, tomllib.TOMLDecodeError) as error:
        report("fail", "caps-remap", f"cannot read {live_omniwm}: {error}")
    else:
        remapped = caps_lock_remapped_to_f18(runner("hidutil", "property", "--get", "UserKeyMapping"))
        if not hyper_wanted:
            report("ok", "caps-remap", "Caps Lock Hyper not enabled")
        elif remapped:
            report("ok", "caps-remap", "Caps Lock is mapped to F18 for Hyper")
        else:
            report("fail", "caps-remap", "Caps Lock Hyper is enabled but the F18 remap is missing; relaunch OmniWM")

    drift = [
        ("omniwm-seed", repo / "apps/omniwm/settings.toml", live_omniwm, "make omniwm-harvest or omniwm-deploy"),
        ("ghostty-seed", repo / "apps/ghostty/config", home / ".config/ghostty/config", "make ghostty-harvest or ghostty-deploy"),
        ("skhdrc", repo / ".skhdrc", home / ".skhdrc", "make switch"),
    ]
    for name, seed, live, fix in drift:
        if same_file(seed, live):
            report("ok", name, "matches live file")
        else:
            report("warn", name, f"differs from {live}; run: {fix}")

    return results


def main() -> int:
    results = check_stack(Path.home(), REPO_ROOT)
    for status, name, detail in results:
        print(f"{status.upper():5} {name:14} {detail}")
    return 1 if any(status == "fail" for status, _, _ in results) else 0


if __name__ == "__main__":
    sys.exit(main())
