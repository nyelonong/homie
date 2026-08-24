#!/bin/sh
# Fresh-machine bootstrap: Nix, this repository, Home Manager, and pinned runtimes.
# Usage: curl -fsSL https://raw.githubusercontent.com/nyelonong/homie/main/bootstrap.sh | sh
set -eu

REPO_HTTPS="https://github.com/nyelonong/homie.git"
REPO_SSH="git@github.com:nyelonong/homie.git"
REPO_DIR="$HOME/homie"
KEY_DIR="$HOME/.ssh"
KEY="$KEY_DIR/id_ed25519"

say() { printf '\n==> %s\n' "$*"; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}
run_git() {
  if command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
    git "$@"
  else
    nix run nixpkgs#git -- "$@"
  fi
}

os="$(uname -s)"
case "$os" in
  Darwin) ;;
  Linux)
    kernel_release="$(uname -r | tr '[:upper:]' '[:lower:]')"
    case "$kernel_release" in
      *microsoft* | *wsl*) ;;
      *) die "unsupported Linux environment: this repository supports WSL" ;;
    esac
    ;;
  *) die "unsupported OS: $os" ;;
esac

if [ -z "${PROFILE:-}" ]; then
  if [ "$os" = "Linux" ]; then
    PROFILE="zaki@windows"
  else
    PROFILE="zaki"
  fi
fi
case "$os:$PROFILE" in
  Darwin:zaki | Darwin:zaki@cekat | Linux:zaki@windows) ;;
  *) die "profile $PROFILE is not supported on $os" ;;
esac

if command -v nix >/dev/null 2>&1; then
  say "nix already installed"
else
  say "installing nix (Determinate Systems installer)"
  curl --proto '=https' --tlsv1.2 -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
fi
if ! command -v nix >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

if [ -e "$REPO_DIR" ]; then
  if [ ! -e "$REPO_DIR/.git" ] || [ ! -f "$REPO_DIR/flake.nix" ]; then
    die "$REPO_DIR exists but is not the homie Git repository"
  fi

  remote="$(run_git -C "$REPO_DIR" remote get-url origin)"
  case "$remote" in
    "$REPO_HTTPS" | "$REPO_SSH" | ssh://git@github.com/nyelonong/homie.git) ;;
    *) die "unexpected origin for $REPO_DIR: $remote" ;;
  esac

  branch="$(run_git -C "$REPO_DIR" symbolic-ref --short HEAD)"
  [ "$branch" = "main" ] || die "$REPO_DIR must be on main, found $branch"
  if [ -n "$(run_git -C "$REPO_DIR" status --porcelain)" ]; then
    die "$REPO_DIR has uncommitted changes; preserve them before rerunning bootstrap"
  fi

  say "updating $REPO_DIR"
  run_git -C "$REPO_DIR" fetch --prune origin
  run_git -C "$REPO_DIR" merge --ff-only origin/main
else
  say "cloning $REPO_HTTPS"
  run_git clone "$REPO_HTTPS" "$REPO_DIR"
fi

if [ -f "$KEY" ]; then
  say "ssh key exists: $KEY"
else
  say "generating ssh key (needed later if you want to push private repos)"
  mkdir -p "$KEY_DIR"
  chmod 700 "$KEY_DIR"
  ssh-keygen -t ed25519 -C "$(id -un)@$(hostname)" -f "$KEY"
  say "add this public key to GitHub when convenient: https://github.com/settings/ssh/new"
  cat "$KEY.pub"
fi

say "applying Home Manager configuration (profile: $PROFILE)"
nix run "$REPO_DIR#home-manager" -- switch --flake "$REPO_DIR#$PROFILE"

say "installing pinned language runtimes"
nix run "$REPO_DIR#mise" -- install --yes

say "done — restart your shell"
