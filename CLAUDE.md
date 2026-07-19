# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Personal dotfiles managed declaratively via a **Nix flake + home-manager** on **macOS (aarch64-darwin)** for the single user `zaki`. There is no application code, build, or test suite — the "build" is materializing the home environment.

## Commands

```bash
# Apply the configuration (the primary command — run after any change)
home-manager switch --flake .#zaki

# Update flake inputs (nixpkgs-unstable, home-manager) and apply
nix flake update && home-manager switch --flake .#zaki

# Format Nix files
nixfmt *.nix

# Inspect the flake / what was built
nix flake show
ls -l result   # symlink to the last-built generation in /nix/store
```

There is no lint or test step. Validation = `home-manager switch` succeeds and the resulting shell behaves.

## Architecture

The config flows through three layers:

1. **`flake.nix`** — declares inputs (`nixpkgs-unstable`, `home-manager` following nixpkgs) and exposes `homeConfigurations."zaki"`, pinned to `aarch64-darwin`, with `./home.nix` as its only module.

2. **`home.nix`** — the single home-manager module and the heart of the repo. It does two distinct jobs:
   - **`home.packages`**: the declarative package list (git/gh/delta, nixfmt/nil, pnpm, eza, bat, fd, ripgrep, jq, tealdeer, nerdfonts). Add CLI tools here, not via brew — except language runtimes, which mise owns (see below). `jq` is load-bearing: `.claude/statusline-command.sh` shells out to it.
   - **`home.file.*`**: symlinks repo files into `$HOME` (`./config` → `~/.config`, plus `.zshrc`, `.gitconfig`, `.claude/statusline-command.sh`). **Edits to dotfiles must be made in the repo copy** — the home directory versions are read-only symlinks into `/nix/store` and are overwritten on every `switch`.
   - Also enables `programs.{home-manager,direnv,mise,zsh,zoxide,fzf,atuin,starship}`. Shell aliases, session vars, and the Ctrl-R keybind live in `programs.zsh` here, not in a sourced file.

3. **Sourced shell config** (`.zshrc`, `config/starship.toml`) — the leftover runtime bits kept as plain files. `.zshrc` is now nearly empty (one PATH line); everything else moved into `programs.zsh`.

### Things worth knowing before editing

- **Two package-management systems coexist by design.** Nix owns most tooling, but **language runtimes are managed by [mise](https://mise.jdx.dev)**, not `home.packages` — a project can then override the global version with its own `mise.toml`/`.tool-versions`. The global pins live in `programs.mise.globalConfig.tools` in `home.nix` (currently go/node/python); `switch` writes them to `~/.config/mise/config.toml` and `mise install` materializes them (`bootstrap.sh` runs it; mise also auto-installs a missing tool on first use). To bump a runtime: edit `home.nix`, `make switch`, `mise install`. mise activates via `programs.mise.enableZshIntegration` and manipulates PATH directly — no shims, so `which go` gives the real binary. (Migrated from asdf on 2026-07-14; `~/.asdf` has been removed, and the ruby build deps it needed — libyaml/openssl/readline/gmp/rubyPackages.ffi — dropped from `home.packages` with it.)

- **`NIXPKGS_ALLOW_UNFREE=1`** is set in `home.sessionVariables` — required because the nerdfonts package is unfree. Go env (`GOPATH`/`GOBIN` under `~/Projects/go`) is set there too.

- Shell aliases in `programs.zsh.shellAliases` rewrite common commands (`cat`→`bat`, `ls`/`ll`/`tree`→`eza`), so those binaries must stay in `home.packages`.

- **Zed is intentionally not in `home.packages`.** `.gitconfig` sets `core.editor = zed --wait`, but the `zed` CLI comes from the Zed app itself (Zed → Install CLI → `/usr/local/bin/zed`). nixpkgs' `zed-editor` trails upstream (1.8.2 vs 1.10.3 as of 2026-07-14) and would shadow the self-updating app, so the app stays app-managed and the requirement is documented in the README's new-machine steps instead.

- **`sessionPath` order matters.** It carries `~/.local/share/mise/shims` because `programs.mise`'s PATH activation only runs in *interactive* zsh — non-interactive shells (Claude Code hooks, editors, launchd) need the shims to see node/go/python. Removing it breaks hooks with `node: command not found`.

## Claude Code

Only `.claude/statusline-command.sh` is managed here (symlinked via `home.file`, edit the repo copy). The rest of `~/.claude/` — settings, instructions, rules, commands, plugins, skills, MCP servers — is set up per-machine by Claude Code itself and is intentionally not tracked. (An earlier revision synced CLAUDE.md/RTK.md/rules/commands/settings.json plus a `scripts/bootstrap-claude.sh` plugin installer — see git history if that's ever wanted again.)

**One exception: a curated skill/plugin baseline.** `bootstrap.sh` installs a fixed set of Claude Code skills, plugins, and MCP servers on every machine, via three mechanisms — git-cloned skill packs symlinked into `~/.claude/skills`, `claude plugin install`, and `claude mcp add`. Current set: the samber golang pack + a bespoke `go-network-resiliency`, a TypeScript pack, **galdr** (the bespoke methodology pack, installed as a plugin straight from its private GitHub repo `nyelonong/galdr` with its SessionStart hook enabled — it replaced superpowers and the Matt Pocock pack on 2026-07-19; on a new machine this needs the generated SSH key registered on GitHub first, or the step self-skips with a warning), design + frontend-design, gopls + typescript LSPs, Warp, Playwright, and the Context7 MCP. The two repo-owned pieces live under `./skills/`: `go-network-resiliency/SKILL.md` and `CLAUDE.global.md` (the global "always use the `golang-*` skills" rule, appended once to `~/.claude/CLAUDE.md`). Everything else is pulled from upstream. Edit the baseline in `bootstrap.sh`.

## Adding a new machine

One command on a fresh macOS or WSL2 machine. The repo is public, so
`bootstrap.sh` is fetched directly — no gist indirection needed. It installs
Nix (Determinate), clones this repo to `~/homie` over HTTPS (read-only, no
auth needed), generates an SSH key for pushing back later, then applies the
right profile, installs claude-code + rtk, and applies the curated
skill/plugin/MCP baseline described above:

```sh
curl -fsSL https://raw.githubusercontent.com/nyelonong/homie/main/bootstrap.sh | sh
```

Re-runnable — steps skip or harmlessly re-apply work already done. `PROFILE`
overrides the OS-based default, set on `sh` (the right side of the pipe),
not on `curl`:

```sh
curl -fsSL https://raw.githubusercontent.com/nyelonong/homie/main/bootstrap.sh | PROFILE=zaki sh
```

(`PROFILE` is `zaki` or `zaki@windows`.)
