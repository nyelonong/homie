# AGENTS.md

This file provides guidance to coding agents working in this repository.

## What this is

Personal dotfiles managed declaratively with a **Nix flake + Home Manager** for three active profiles: `zaki` (personal mac, aarch64-darwin), `zaki@cekat` (work mac, aarch64-darwin), and `zaki@windows` (WSL2, x86_64-linux). There is no application build; validation checks configuration and materializes the home environment.

## Commands

```bash
# Apply with the Home Manager version locked by this flake
make switch                     # PROFILE=zaki default

# OmniWM: the live settings file is app-owned, not a symlink
make omniwm-deploy              # stop app, push seed → live file, restart
make omniwm-harvest             # pull live file → seed for review

# Ghostty: the live config file is app-owned, not a symlink
make ghostty-deploy             # push seed → live config
make ghostty-harvest            # pull live config → seed for review

# Update locked inputs and apply
make update

# Repository gate
make fmt                        # format every Nix file; validate OmniWM settings
make check                      # formatting, shell, bootstrap, profile, OmniWM checks

# Inspect outputs
nix flake show
```

Validation = `make check`, the relevant native activation package builds, `make switch` succeeds, and the resulting shell behaves. CI builds all three active profiles on their native platforms.

## Architecture

The configuration has four layers:

1. **`flake.nix`** declares locked nixpkgs and Home Manager inputs, exposes the locked `home-manager` and `mise` apps for both supported systems, and defines the three active `homeConfigurations`. Each profile combines `(import ./home.nix)` with one module from `hosts/`.

2. **`home.nix`** is the ordered shared-module manifest, not a large option module:
   - **`modules/base.nix`** owns shared CLI packages, `GOPATH`/`GOBIN`, session PATH, fonts, XDG enablement, and static dotfile mappings. Add CLI tools here. Add a `home.file` entry when adding a file under `config/`.
   - **`modules/runtimes.nix`** owns direnv, mise integration, and global runtime pins.
   - **`modules/shell.nix`** owns shared Zsh aliases, generic Pi provider wrappers, zoxide, fzf, and Starship.
   - **`modules/skhd.nix`** owns skhd, `~/.skhdrc`, its launchd agent, and reload activation for Darwin profiles.
   - **`modules/ghostty.nix`** owns the Ghostty seed and the app-owned live config for Darwin profiles.
   - **`modules/omniwm.nix`** owns the OmniWM settings seed for Darwin profiles.

3. **`hosts/`** contains active profile ownership:
   - `personal.nix` owns personal-only packages and environment overrides.
   - `cekat.nix` owns work-only packages, kubectl aliases, and Go scopes.
   - `windows.nix` owns WSL identity and home paths.
   Darwin-only behavior shared by both macOS profiles is gated by `pkgs.stdenv.hostPlatform.isDarwin`.

4. **Configuration sources are separated by writer ownership.** `config/` mirrors paths below `~/.config`; `.gitconfig` and `.skhdrc` mirror files directly below `$HOME`. Home Manager deploys these as read-only store files. `apps/omniwm/settings.toml` and `apps/ghostty/config` are seeds because their live files remain writable and app-owned.

`history/hosts/` contains inactive ByteDance and Tokopedia records. They preserve former-employer history and must not be imported into `flake.nix` or presented as supported profiles.

### Things worth knowing before editing

- **Three package sources coexist by design.** Nix owns CLI tools; mise owns language runtimes; Brew owns macOS GUI applications and anything not suited to Nix. Do not move language runtimes into `home.packages` or CLI tools into Brew.
- **`config/` follows target paths.** `config/starship.toml` is intentionally flat because its target is `~/.config/starship.toml`; Helix and Zed keymap use nested target directories. App-owned settings such as OmniWM and Zed live under `apps/`.
- **Zed's shared seed must remain strict JSON.** `make validate-zed` checks `apps/zed/settings.json`; JSON comments and trailing commas are not supported.
- **New static config needs an explicit mapping.** `modules/base.nix` no longer recursively links all of `config/`, allowing profile-specific overrides. App-owned settings are seeded by activation and remain writable by the app.
- **App-owned settings use seeds.** Graduate a tool from `config/` to `apps/<tool>/` when its live file must stay writable instead of a read-only symlink. Add explicit deploy/harvest behavior rather than making the live file read-only.
- **Runtime pins live in `modules/runtimes.nix`.** After changing one, run `make switch` and `mise install`. Projects may still override pins with `mise.toml` or `.tool-versions`.
- **`NIXPKGS_ALLOW_UNFREE=1`**, `GOPATH`, `GOBIN`, and the mise shim fallback live in `modules/base.nix`. The shim path is required by non-interactive shells, editors, hooks, and launchd.
- **Shell aliases live in `modules/shell.nix`.** They depend on their corresponding packages in `modules/base.nix`.
- **Checks discover existing tracked and untracked Nix files.** Keep the `NIX_FILES` filter tolerant of deleted paths so formatting works during file moves.

## Adding a new machine

The public bootstrap entry point is:

```sh
curl -fsSL https://raw.githubusercontent.com/nyelonong/homie/main/bootstrap.sh | sh
```

It installs Nix when needed, clones or validates `~/homie`, requires the expected origin and a clean `main`, fetches and fast-forwards without rewriting history, generates an SSH key when absent, applies a platform-compatible profile through the locked Home Manager app, and installs pinned runtimes through the locked mise app.

`PROFILE` is set on `sh`, not `curl`:

```sh
curl -fsSL https://raw.githubusercontent.com/nyelonong/homie/main/bootstrap.sh | PROFILE=zaki sh
```

Bootstrap supports macOS and WSL only. It rejects generic Linux, incompatible profiles, unexpected repositories, dirty worktrees, non-main branches, and non-fast-forward updates. Use `make switch` rather than bootstrap when intentionally testing local uncommitted configuration.
