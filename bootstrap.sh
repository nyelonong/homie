#!/bin/sh
# Fresh-machine bootstrap: nix + clone + home-manager + AI agent tools.
# Usage: curl -fsSL https://raw.githubusercontent.com/nyelonong/homie/main/bootstrap.sh | sh
# Re-runnable: every step skips work already done. PROFILE=... overrides the
# OS-based default (zaki on macOS, zaki@windows on WSL2).
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
# is just for pushing back later. Skipped silently if a key already exists.
if [ -f "$KEY" ]; then
  say "ssh key exists: $KEY"
else
  say "generating ssh key (needed later if you want to push)"
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

# AI agent tools — official installers drop binaries into ~/.local/bin (on
# home.sessionPath for interactive shells, but not necessarily this one), so put
# it on PATH before the claude/rtk guards and the plugin/mcp/skill steps below.
export PATH="$HOME/.local/bin:$PATH"

if command -v claude >/dev/null 2>&1; then
  say "claude-code already installed"
else
  say "installing claude-code"
  curl -fsSL https://claude.ai/install.sh | bash
fi

if command -v rtk >/dev/null 2>&1; then
  say "rtk already installed"
else
  say "installing rtk"
  curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
fi

# --- Baseline agent skills, plugins, and MCP servers -----------------------
# A curated set installed on every machine, via three mechanisms:
#   skill packs -> git clone into ~/.agents/skills, symlinked into ~/.claude/skills
#   plugins     -> claude plugin marketplace add + install
#   MCP servers -> claude mcp add
# All steps are idempotent (re-run safely). claude-code owns ~/.claude, so these
# live here in bootstrap, not in home.nix.
say "installing baseline agent skills / plugins / MCP"

AGENTS_SKILLS="$HOME/.agents/skills"
CLAUDE_SKILLS="$HOME/.claude/skills"
mkdir -p "$AGENTS_SKILLS" "$CLAUDE_SKILLS"

git_sync() { # <url> <dest>: shallow clone once, fast-forward on re-run
  if [ -d "$2/.git" ]; then
    nix run nixpkgs#git -- -C "$2" pull --ff-only --quiet || true
  else
    nix run nixpkgs#git -- clone --depth 1 --quiet "$1" "$2"
  fi
}
link_skill() { # <abs skill dir under $AGENTS_SKILLS>: symlink into ~/.claude/skills
  ln -sfn "../../.agents/skills/${1#"$AGENTS_SKILLS"/}" "$CLAUDE_SKILLS/$(basename "$1")"
}

# golang pack (all skills)
git_sync https://github.com/samber/cc-skills-golang.git "$AGENTS_SKILLS/cc-skills-golang"
for d in "$AGENTS_SKILLS"/cc-skills-golang/skills/*/; do link_skill "${d%/}"; done

# bespoke go-network-resiliency — source of truth lives in this repo
ln -sfn "$REPO_DIR/skills/go-network-resiliency" "$AGENTS_SKILLS/go-network-resiliency"
link_skill "$AGENTS_SKILLS/go-network-resiliency"

# TypeScript (dedicated single-skill pack)
git_sync https://github.com/SpillwaveSolutions/mastering-typescript-skill.git "$AGENTS_SKILLS/mastering-typescript-skill"
find "$AGENTS_SKILLS/mastering-typescript-skill" -name SKILL.md | while IFS= read -r f; do
  link_skill "$(dirname "$f")"
done

# Matt Pocock's pack and superpowers were retired 2026-07-19 — replaced by galdr,
# the bespoke methodology pack (installed as a plugin in the auth-gated block below).

# Plugins + MCP need a signed-in claude-code; on a fresh machine that hasn't
# happened yet, so gate them and nudge rather than silently no-op. (The skill
# packs above and the global rule below need no auth — they always run.)
if claude auth status >/dev/null 2>&1; then
  # Claude Code plugins (marketplaces first, then install if missing)
  for m in anthropics/claude-plugins-official anthropics/knowledge-work-plugins warpdotdev/claude-code-warp; do
    claude plugin marketplace add "$m" >/dev/null 2>&1 || true
  done
  for p in \
    gopls-lsp@claude-plugins-official \
    typescript-lsp@claude-plugins-official \
    frontend-design@claude-plugins-official \
    playwright@claude-plugins-official \
    design@knowledge-work-plugins \
    warp@claude-code-warp; do
    claude plugin list 2>/dev/null | grep -q "$p" || claude plugin install "$p" >/dev/null 2>&1 || true
  done

  # galdr — the bespoke methodology pack (v0.1.0+; replaced superpowers + mattpocock).
  # Cloned over SSH (private repo) — on a brand-new machine this needs the generated
  # SSH key registered on GitHub first; until then the step self-skips with a warning.
  GALDR_REPO="$HOME/Projects/personal/galdr"
  [ -d "$GALDR_REPO/.git" ] || git_sync git@github.com:nyelonong/galdr.git "$GALDR_REPO" || true
  if [ -d "$GALDR_REPO/.claude-plugin" ]; then
    claude plugin marketplace add "$GALDR_REPO" >/dev/null 2>&1 || true
    claude plugin list 2>/dev/null | grep -q galdr || claude plugin install galdr@galdr-local >/dev/null 2>&1 || true
    # enable the SessionStart bootstrap (the flag file is gitignored, so a fresh
    # install ships with the hook off; the trial gate passed 2026-07-19, so on)
    d=$(ls -d "$HOME/.claude/plugins/cache/galdr-local/galdr"/*/ 2>/dev/null | sort -V | tail -1)
    [ -n "$d" ] && touch "${d}hooks/enabled"
  else
    say "galdr repo missing at $GALDR_REPO — copy it over, re-run bootstrap (methodology pack skipped)"
  fi

  # MCP: Context7 (live library docs), user scope
  claude mcp list 2>/dev/null | grep -qi context7 ||
    claude mcp add --scope user --transport http context7 https://mcp.context7.com/mcp >/dev/null 2>&1 || true
else
  say "skipped plugins + MCP — claude-code isn't signed in yet"
  say "  sign in with 'claude auth login', then re-run this bootstrap to finish them"
fi

# Global rule: force-trigger the golang skills on any Go work, in any project
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
if ! { [ -f "$CLAUDE_MD" ] && grep -q "homie:baseline-golang" "$CLAUDE_MD"; }; then
  say "adding global golang skill-trigger rule (~/.claude/CLAUDE.md)"
  { printf '\n'; cat "$REPO_DIR/skills/CLAUDE.global.md"; } >>"$CLAUDE_MD"
fi

say "done — restart your shell"
