# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## What this is

Personal dotfiles managed declaratively via a **Nix flake + home-manager** for user `zaki`, across three profiles: `zaki` (personal mac, aarch64-darwin), `zaki@cekat` (work mac, aarch64-darwin), `zaki@windows` (WSL2, x86_64-linux). There is no application build; validation checks configuration and materializes the home environment.

## Commands

```bash
# Apply the configuration (the primary command — run after any change)
make switch                     # = home-manager switch --flake .#$(PROFILE), default zaki

# OmniWM (mac): its live settings file is app-owned, not a symlink
make omniwm-deploy              # push repo seed → live file, restart OmniWM
make omniwm-harvest             # pull live file → repo seed for review, then commit

# Update flake inputs (nixpkgs-unstable, home-manager) and apply
make update

# Format and validate
make fmt                        # format Nix files and validate OmniWM settings
make check                      # formatting, shell, and OmniWM deployment checks

# Inspect the flake / what was built
nix flake show
ls -l result   # symlink to the last-built generation in /nix/store
```

Validation = `make check`, the relevant profile activation package builds, `home-manager switch` succeeds, and the resulting shell behaves.

## Architecture

The config flows through three layers:

1. **`flake.nix`** — declares inputs (`nixpkgs-unstable`, `home-manager` following nixpkgs) and exposes one `homeConfiguration` per profile (`zaki`, `zaki@cekat`, `zaki@windows`), each combining `./home.nix` with a per-machine module from `./hosts/` (username/homeDirectory).

2. **`home.nix`** — the single home-manager module and the heart of the repo. It does three distinct jobs:
   - **`home.packages`**: the declarative package list (git/gh/delta, nixfmt/nil, eza, bat, fd, ripgrep, jq, tealdeer, nerdfonts) plus a darwin-only block (`lib.optionals pkgs.stdenv.isDarwin`, currently skhd). Add CLI tools here — not via brew for CLI tools, not at all for language runtimes (mise owns those) or mac GUI apps (brew casks; see below).
   - **`home.file.*`**: symlinks repo files into `$HOME` (`./config` → `~/.config`, plus `.gitconfig` and `.skhdrc`). **Edits to dotfiles must be made in the repo copy** — the home directory versions are read-only symlinks into `/nix/store` and are overwritten on every `switch`. Exception: `apps/` seeds (below).
   - Also enables `programs.{home-manager,direnv,mise,zsh,zoxide,fzf,atuin,starship}`. Shell aliases, session vars, and the Ctrl-R keybind live in `programs.zsh` here, not in a sourced file.

   Mac desktop layer (darwin-guarded, added 2026-08-22):
   - **`launchd.agents`**: `skhd` runs from its Nix store path. Never hand-written plists.
   - **Activation hooks**: `reloadSkhd` runs `skhd -r` after every switch so keymap edits land immediately; `seedOmniWM` installs a writable OmniWM seed only when the live file is missing or still one of our old symlinks.

3. **Shell runtime config** (`programs.zsh`, `config/starship.toml`, optional `~/.zshrc.local`) — home-manager generates `.zshrc`; the unmanaged local file is sourced for machine-specific additions.

### Things worth knowing before editing

- **Three package sources coexist by design.** Nix owns CLI tooling; [mise](https://mise.jdx.dev) owns language runtimes (see below); **brew** owns mac GUI apps and anything unpackagable — currently Karabiner-Elements and OmniWM (cask from `barutsrb/tap`). Don't force these into Nix.
- **Two config-deployment classes, chosen by who writes the file last.** Hand-edited dotfiles (starship, helix, `.skhdrc`) live in `config/` and deploy as read-only store symlinks — edit repo, `make switch`. Apps that rewrite their own settings (currently OmniWM) get a **seed** in `apps/<tool>/`: the live file stays plain and app-owned; `make <tool>-deploy` pushes the seed over it, `make <tool>-harvest` pulls GUI changes back for review before committing. Graduate a tool to this class on the first "would be clobbered" failure or an app-replaced symlink.
- **Language runtimes are managed by [mise](https://mise.jdx.dev)**, not `home.packages` — a project can then override the global version with its own `mise.toml`/`.tool-versions`. The global pins live in `programs.mise.globalConfig.tools` in `home.nix`; `switch` writes them to `~/.config/mise/config.toml` and `mise install` materializes them (`bootstrap.sh` runs it; mise also auto-installs a missing tool on first use). To bump a runtime: edit `home.nix`, `make switch`, `mise install`. mise activates via `programs.mise.enableZshIntegration` and manipulates PATH directly — no shims, so `which go` gives the real binary. (Migrated from asdf on 2026-07-14; `~/.asdf` has been removed, and the ruby build deps it needed — libyaml/openssl/readline/gmp/rubyPackages.ffi — dropped from `home.packages` with it.)

- **`NIXPKGS_ALLOW_UNFREE=1`** is set in `home.sessionVariables` — required because the nerdfonts package is unfree. Go env (`GOPATH`/`GOBIN` under `~/Projects/go`) is set there too.

- Shell aliases in `programs.zsh.shellAliases` rewrite common commands (`cat`→`bat`, `ls`/`ll`/`tree`→`eza`), so those binaries must stay in `home.packages`.

- **`sessionPath` order matters.** It carries `~/.local/share/mise/shims` because `programs.mise`'s PATH activation only runs in *interactive* zsh — non-interactive shells (editors, hooks, launchd) need the shims to see node/go/python. Removing it breaks them with `node: command not found`.

## Adding a new machine

The repo is public, so `bootstrap.sh` is fetched directly — no gist indirection needed. It installs Nix (Determinate), clones this repo to `~/homie` over HTTPS (read-only, no auth needed), generates an SSH key for pushing back later, then applies the right profile and installs the pinned language runtimes:

```sh
curl -fsSL https://raw.githubusercontent.com/nyelonong/homie/main/bootstrap.sh | sh
```

Re-runnable — steps skip or harmlessly re-apply work already done. `PROFILE` overrides the OS-based default, set on `sh` (the right side of the pipe), not on `curl`:

```sh
curl -fsSL https://raw.githubusercontent.com/nyelonong/homie/main/bootstrap.sh | PROFILE=zaki sh
```

Afterwards: restart the shell.

See `README.md` for the human-facing quickstart and `docs/superpowers/specs/2026-07-13-bootstrap-design.md` for design rationale (predates the public-repo simplification).
