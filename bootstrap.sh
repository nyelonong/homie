#!/bin/sh
# Fresh-machine bootstrap: nix + clone + home-manager. OS/dotfiles/packages only.
# Usage: curl -fsSL https://raw.githubusercontent.com/nyelonong/homie/main/bootstrap.sh | sh
# Re-runnable: every step skips work already done. PROFILE=... overrides the
# OS-based default (zaki on macOS, zaki@windows on WSL2).
#
# Claude Code agent config (skills, plugins, MCP, galdr, the claude-code + rtk
# binaries) is NOT installed here — it lives in the separate nyelonong/agents
# repo. Run that after this: git clone git@github.com:nyelonong/agents.git and
# ./bootstrap.sh (see the note at the end).
set -eu

REPO_HTTPS="https://github.com/nyelonong/homie.git"
REPO_DIR="$HOME/homie"
KEY="$HOME/.ssh/id_ed25519"

say() { printf '\n==> %s\n' "$*"; }

os="$(uname -s)"
case "$os" in
  Darwin | Linux) ;;
  *)
    echo "unsupported OS: $os" >&2
    exit 1
    ;;
esac

if command -v nix >/dev/null 2>&1; then
  say "nix already installed"
else
  say "installing nix (Determinate Systems installer)"
  curl --proto '=https' --tlsv1.2 -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
fi
# the installer only edits shell rc files; load nix into THIS shell
if ! command -v nix >/dev/null 2>&1; then
  # This file only exists after nix installation; shellcheck can't verify at linting time
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

if [ -d "$REPO_DIR" ]; then
  say "repo exists: $REPO_DIR"
else
  say "cloning $REPO_HTTPS"
  nix run nixpkgs#git -- clone "$REPO_HTTPS" "$REPO_DIR"
fi

# not needed for the clone above (public repo, read-only over HTTPS) — this
# is just for pushing back later, and for the private agents/galdr repos. Skipped
# silently if a key already exists.
if [ -f "$KEY" ]; then
  say "ssh key exists: $KEY"
else
  say "generating ssh key (needed later if you want to push, and for nyelonong/agents)"
  ssh-keygen -t ed25519 -C "$(id -un)@$(hostname)" -f "$KEY"
  say "add this public key to GitHub when convenient: https://github.com/settings/ssh/new"
  cat "$KEY.pub"
fi

if [ -z "${PROFILE:-}" ]; then
  if [ "$os" = "Linux" ]; then
    PROFILE="zaki@windows"
  else
    PROFILE="zaki"
  fi
fi

say "applying home-manager configuration (profile: $PROFILE)"
nix run github:nix-community/home-manager -- switch --flake "$REPO_DIR#$PROFILE"

# language runtimes pinned in home.nix (programs.mise.globalConfig.tools);
# the switch above wrote ~/.config/mise/config.toml, this materializes it
say "installing pinned language runtimes"
nix run nixpkgs#mise -- install --yes

say "done — restart your shell"
say "next (Claude Code agent config): clone nyelonong/agents and run its bootstrap"
say "  git clone git@github.com:nyelonong/agents.git ~/Projects/personal/agents"
say "  ~/Projects/personal/agents/bootstrap.sh"
