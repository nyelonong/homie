import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
ROUTER = ROOT / "scripts/omniwm-display-routing"
HEADER = "ID\tNAME\tMAIN\tCURRENT\tORIENTATION\tACTIVE WORKSPACE\tFRAME"


class OmniWMDisplayRoutingTest(unittest.TestCase):
    def test_h27g30q_keeps_only_workspace_1_external(self) -> None:
        moves = self.run_router(
            displays=[
                "display:3\tH27G30Q\tno\t-\t-\t-\t0,982 2560x1440",
                "display:1\tBuilt-in Retina Display\tyes\t-\t-\t-\t0,0 1512x982",
            ],
            workspace_displays={1: "H27G30Q", 2: "H27G30Q", 3: "H27G30Q"},
        )

        self.assertEqual(moves, ["2 down --force", "3 down --force"])

    def test_h27g30q_targets_the_built_in_display_even_when_external_is_main(self) -> None:
        moves = self.run_router(
            displays=[
                "display:3\tH27G30Q\tyes\t-\t-\t-\t0,0 2560x1440",
                "display:1\tBuilt-in Retina Display\tno\t-\t-\t-\t0,-982 1512x982",
            ],
            workspace_displays={1: "H27G30Q", 2: "H27G30Q", 3: "H27G30Q"},
        )

        self.assertEqual(moves, ["2 down --force", "3 down --force"])

    def test_s24r35x_keeps_workspaces_1_through_3_external(self) -> None:
        moves = self.run_router(
            displays=[
                "display:2\tS24R35x\tno\t-\t-\t-\t1512,0 1920x1080",
                "display:1\tBuilt-in Retina Display\tyes\t-\t-\t-\t0,0 1512x982",
            ],
            workspace_displays={1: "Built-in Retina Display", 2: "S24R35x", 3: "Built-in Retina Display"},
        )

        self.assertEqual(moves, ["1 right --force", "3 right --force"])

    def test_no_external_display_leaves_native_laptop_fallback_untouched(self) -> None:
        moves = self.run_router(
            displays=["display:1\tBuilt-in Retina Display\tyes\t-\t-\t-\t0,0 1512x982"],
            workspace_displays={
                1: "Built-in Retina Display",
                2: "Built-in Retina Display",
                3: "Built-in Retina Display",
            },
        )

        self.assertEqual(moves, [])

    def test_h27g30q_has_deterministic_precedence_when_both_are_connected(self) -> None:
        moves = self.run_router(
            displays=[
                "display:3\tH27G30Q\tno\t-\t-\t-\t1512,0 2560x1440",
                "display:2\tS24R35x\tno\t-\t-\t-\t-1920,0 1920x1080",
                "display:1\tBuilt-in Retina Display\tyes\t-\t-\t-\t0,0 1512x982",
            ],
            workspace_displays={
                1: "Built-in Retina Display",
                2: "H27G30Q",
                3: "H27G30Q",
            },
        )

        self.assertEqual(moves, ["1 right --force", "2 left --force", "3 left --force"])

    def run_router(self, displays: list[str], workspace_displays: dict[int, str]) -> list[str]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            moves = root / "moves"
            fake_omniwmctl = root / "omniwmctl"
            fake_omniwmctl.write_text(
                """#!/bin/sh
set -eu
if [ "$1" = query ] && [ "$2" = displays ]; then
  printf '%s\\n' "$OMNIWM_TEST_DISPLAYS"
  exit 0
fi
if [ "$1" = query ] && [ "$2" = workspaces ]; then
  workspace=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = --workspace ]; then
      workspace="$2"
      break
    fi
    shift
  done
  case "$workspace" in
    1) printf '%s\\n' "$OMNIWM_TEST_WORKSPACE_1" ;;
    2) printf '%s\\n' "$OMNIWM_TEST_WORKSPACE_2" ;;
    3) printf '%s\\n' "$OMNIWM_TEST_WORKSPACE_3" ;;
  esac
  exit 0
fi
if [ "$1" = workspace ] && [ "$2" = move-to-monitor ]; then
  printf '%s %s %s\\n' "$3" "$4" "$5" >> "$OMNIWM_TEST_MOVES"
  exit 0
fi
exit 1
"""
            )
            fake_omniwmctl.chmod(0o755)
            workspace_rows = {
                workspace: "\t".join(
                    [
                        f"workspace:{workspace}",
                        str(workspace),
                        display,
                        "niri",
                        "no",
                        "no",
                        "total=0, tiled=0, floating=0, scratchpad=0",
                        "-",
                    ]
                )
                for workspace, display in workspace_displays.items()
            }
            environment = {
                **os.environ,
                "OMNIWMCTL": str(fake_omniwmctl),
                "OMNIWM_TEST_DISPLAYS": "\n".join([HEADER, *displays]),
                "OMNIWM_TEST_WORKSPACE_1": "\n".join(["ID\tWORKSPACE\tDISPLAY", workspace_rows[1]]),
                "OMNIWM_TEST_WORKSPACE_2": "\n".join(["ID\tWORKSPACE\tDISPLAY", workspace_rows[2]]),
                "OMNIWM_TEST_WORKSPACE_3": "\n".join(["ID\tWORKSPACE\tDISPLAY", workspace_rows[3]]),
                "OMNIWM_TEST_MOVES": str(moves),
            }

            subprocess.run(["sh", str(ROUTER)], cwd=ROOT, env=environment, check=True)

            return moves.read_text().splitlines() if moves.exists() else []


if __name__ == "__main__":
    unittest.main()
