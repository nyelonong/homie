import argparse
import os
import stat
import tempfile
import tomllib
from pathlib import Path


def transfer_config(source: Path, destination: Path) -> bool:
    content = source.read_bytes()
    tomllib.loads(content.decode("utf-8"))

    try:
        if (
            not destination.is_symlink()
            and destination.read_bytes() == content
            and stat.S_IMODE(destination.stat().st_mode) == 0o644
        ):
            return False
    except FileNotFoundError:
        pass

    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix=f".{destination.name}.", dir=destination.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(content)
            os.fchmod(output.fileno(), 0o644)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)
    return True


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        changed = transfer_config(args.source, args.destination)
    except (UnicodeError, tomllib.TOMLDecodeError):
        parser.exit(1, f"invalid UTF-8 TOML: {args.source}\n")
    except OSError as error:
        parser.exit(1, f"config transfer failed: {error}\n")
    print("configuration updated" if changed else "no changes")


if __name__ == "__main__":
    main()
