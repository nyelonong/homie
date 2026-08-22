#!/usr/bin/env python3
"""Validate the OmniWM seed against the settings format used by the app."""

from pathlib import Path
import sys
import tomllib


VALID_KEYS = {
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
    "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "Equal", "Minus", "Left Bracket", "Right Bracket", "Semicolon", "Quote",
    "Comma", "Period", "Slash", "Grave", "Return", "Tab", "Space", "Delete",
    "Escape", "Home", "End", "Page Up", "Page Down", "Left Arrow", "Right Arrow",
    "Up Arrow", "Down Arrow", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8",
    "F9", "F10", "F11", "F12", "F13", "F14", "F15", "F16", "F17", "F18", "F19",
    "F20", "Unassigned",
}
VALID_MODIFIERS = {"Control", "Option", "Shift", "Command", "Hyper"}


def fail(message: str) -> None:
    print(f"OmniWM validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    path = Path(__file__).resolve().parent.parent / "apps/omniwm/settings.toml"
    try:
        config = tomllib.loads(path.read_text())
    except (OSError, tomllib.TOMLDecodeError) as error:
        fail(f"{path}: {error}")

    for index, hotkey in enumerate(config.get("hotkeys", []), start=1):
        binding = hotkey.get("binding", "Unassigned")
        if binding == "Unassigned":
            continue
        parts = binding.split("+")
        if len(parts) < 2 or any(part not in VALID_MODIFIERS for part in parts[:-1]):
            fail(f"hotkeys[{index}] has unsupported binding format: {binding!r}")
        if parts[-1] not in VALID_KEYS:
            fail(f"hotkeys[{index}] has unsupported key name: {parts[-1]!r}")

    print(f"validated {path}")


if __name__ == "__main__":
    main()
