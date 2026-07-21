<p align="center">
  <a href="flake.nix"><img src="https://img.shields.io/badge/Nix-flake-6e56cf?style=flat-square" alt="Nix flake"></a>
  <a href="https://github.com/nix-community/home-manager"><img src="https://img.shields.io/badge/home--manager-managed-22d3ee?style=flat-square" alt="home-manager managed"></a>
  <img src="https://img.shields.io/badge/platforms-macOS_·_WSL2-34d399?style=flat-square" alt="platforms macOS and WSL2">
  <img src="https://img.shields.io/badge/build-none_·_home--manager_switch-64748b?style=flat-square" alt="no build step">
</p>

<h1 align="center">homie</h1>

<p align="center">
  <b>One command rebuilds my whole shell environment — packages, dotfiles, shell,<br>
  and pinned language runtimes — the same way on macOS and WSL2.</b>
</p>

<p align="center">
  <a href="#what-this-is">What</a> ·
  <a href="#how-it-fits-together">Architecture</a> ·
  <a href="#fresh-machine">Fresh machine</a> ·
  <a href="#daily-use">Daily use</a> ·
  <a href="#layout">Layout</a> ·
  <a href="#rules-of-the-house">Rules</a>
</p>

<p align="center">
  <i>Personal dotfiles as a <a href="flake.nix">Nix flake</a> + <a href="https://github.com/nix-community/home-manager">home-manager</a> — one <code>home.nix</code> module, per-machine overrides in <code>hosts/</code>.</i>
</p>

---

## What this is

My machine setup, declarative and reproducible. Instead of a pile of shell scripts
and hand-installed tools that drift apart across machines, everything — CLI packages,
dotfile symlinks, shell config, pinned runtimes — is one Nix expression. A single
`home-manager switch` materializes it, and it lands the same on my Mac and my WSL2 box.
There is no application code and no test suite here; the "build" is the home environment.

| Profile        | Machine      | System         |
| -------------- | ------------ | -------------- |
| `zaki`         | personal mac | aarch64-darwin |
| `zaki@windows` | WSL2         | x86_64-linux   |

## How it fits together

```mermaid
flowchart LR
    F["flake.nix"] --> H["home.nix"]
    HOST["hosts/*.nix (per-machine)"] --> H
    H --> P["home.packages<br/>git · eza · ripgrep · jq · …"]
    H --> D["home.file<br/>dotfiles symlinked → ~"]
    H --> PR["programs.*<br/>zsh · mise · starship · atuin · direnv"]
```

`flake.nix` exposes one home configuration per profile; each pairs `home.nix` (the shared
module) with a small `hosts/` file for the per-machine username and home directory. Language
runtimes are the one thing Nix does **not** own — [mise](https://mise.jdx.dev) manages
go/node/python so a project can pin its own version.

> **Claude Code agent config is not here.** The `claude-code` binaries, skills, plugins,
> MCP servers, and methodology packs are managed separately, outside this repo. homie is
> dotfiles / packages / home-manager only.

## Fresh machine

One command — no git, nix, or SSH key needed beforehand:

```sh
curl -fsSL https://raw.githubusercontent.com/nyelonong/homie/main/bootstrap.sh | sh
```

It installs Nix (Determinate), clones this repo to `~/homie` over HTTPS (read-only, no auth —
it's public), generates an SSH key for pushing back later, applies the right profile, and
installs the pinned language runtimes. Re-runnable — steps skip or harmlessly re-apply.

`PROFILE` overrides the OS-based default (`zaki` on macOS, `zaki@windows` on WSL2). Set it on
`sh` — the right side of the pipe, not `curl`:

```sh
curl -fsSL https://raw.githubusercontent.com/nyelonong/homie/main/bootstrap.sh | PROFILE=zaki sh
```

Then, the things nix does not do for you:

1. Restart your shell.
2. `claude login` — Claude Code and its agent config are set up separately, outside this repo.

## Daily use

```sh
make switch    # apply config after editing (PROFILE=zaki default)
make update    # bump flake inputs, then apply
make fmt       # format nix files
make help      # list all targets
```

## Layout

```
flake.nix            inputs + one homeConfiguration per profile
home.nix             the module: packages, symlinks, shell, programs
hosts/               per-machine username/homeDirectory overrides
config/              → ~/.config (starship, ntfy, …)
.zshrc, .gitconfig   → symlinked into ~
bootstrap.sh         fresh-machine setup (nix + home-manager only)
```

## Rules of the house

- **Edit files in this repo, not in `~`.** Home versions are read-only symlinks into
  `/nix/store`, overwritten on every `make switch`.
- **New CLI tools go in `home.packages`** (`home.nix`), not brew. Language runtimes are the
  exception — [mise](https://mise.jdx.dev) owns them, pinned under
  `programs.mise.globalConfig.tools`. To bump one: edit that, then `make switch && mise install`.
  Per-project overrides still work — drop a `mise.toml` or `.tool-versions` in the project.
- **`~/.claude` is not tracked here** except `statusline-command.sh`; Claude Code manages the
  rest per-machine, and the agent baseline is set up separately, outside this repo.
