# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## What this is

Personal dotfiles managed declaratively via a **Nix flake + home-manager** for user `zaki`, across two profiles: `zaki` (personal mac, aarch64-darwin), `zaki@windows` (WSL2, x86_64-linux). There is no application code, build, or test suite — the "build" is materializing the home environment.

## Commands

```bash
# Apply the configuration (the primary command — run after any change)
make switch                     # = home-manager switch --flake .#$(PROFILE), default zaki

# Update flake inputs (nixpkgs-unstable, home-manager) and apply
make update

# Format Nix files
make fmt                        # nixfmt *.nix hosts/*.nix

# Inspect the flake / what was built
nix flake show
ls -l result   # symlink to the last-built generation in /nix/store
```

There is no lint or test step. Validation = `home-manager switch` succeeds and the resulting shell behaves. For `bootstrap.sh`, validation = `sh -n` + `shellcheck`.

## Architecture

The config flows through three layers:

1. **`flake.nix`** — declares inputs (`nixpkgs-unstable`, `home-manager` following nixpkgs) and exposes one `homeConfiguration` per profile (`zaki`, `zaki@windows`), each combining `./home.nix` with a per-machine module from `./hosts/` (username/homeDirectory).

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

## Adding a new machine

The repo is public, so `bootstrap.sh` is fetched directly — no gist indirection needed. It installs Nix (Determinate), clones this repo to `~/homie` over HTTPS (read-only, no auth needed), generates an SSH key for pushing back later, then applies the right profile and installs claude-code/rtk/caveman via their official installers:

```sh
curl -fsSL https://raw.githubusercontent.com/nyelonong/homie/main/bootstrap.sh | sh
```

Re-runnable — steps skip or harmlessly re-apply work already done. `PROFILE` overrides the OS-based default, set on `sh` (the right side of the pipe), not on `curl`:

```sh
curl -fsSL https://raw.githubusercontent.com/nyelonong/homie/main/bootstrap.sh | PROFILE=zaki sh
```

Afterwards: restart the shell, then `claude login`.

See `README.md` for the human-facing quickstart and `docs/superpowers/specs/2026-07-13-bootstrap-design.md` for design rationale (predates the public-repo simplification).
