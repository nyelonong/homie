# homie

Personal dotfiles, managed declaratively with a [Nix flake](flake.nix) +
[home-manager](https://github.com/nix-community/home-manager). One `home.nix`
module, per-machine overrides in `hosts/`.

| Profile        | Machine      | System         |
| -------------- | ------------ | -------------- |
| `zaki`         | personal mac | aarch64-darwin |
| `zaki@windows` | WSL2         | x86_64-linux   |

## Fresh machine

One command — no git, nix, or SSH key needed beforehand:

```sh
curl -fsSL https://raw.githubusercontent.com/nyelonong/homie/main/bootstrap.sh | sh
```

It installs Nix (Determinate), clones this repo to `~/homie` over HTTPS
(read-only, no auth needed — it's public), generates an SSH key for pushing
back later, then applies the right profile and installs the pinned language
runtimes. That's it — homie is dotfiles / packages / home-manager only.

Claude Code agent config (the `claude-code` + `rtk` binaries, skills, plugins,
MCP, galdr) lives in the separate private
[`nyelonong/agents`](https://github.com/nyelonong/agents) repo and is a separate
step — see below.

Everything is re-runnable — steps skip or harmlessly re-apply work already
done. `PROFILE` overrides the OS-based default (`zaki` on macOS,
`zaki@windows` on WSL2):

```sh
curl -fsSL https://raw.githubusercontent.com/nyelonong/homie/main/bootstrap.sh | PROFILE=zaki sh
```

Afterwards, things nix does not do for you:

1. restart your shell
2. Claude Code agent config (separate private repo):
   ```sh
   git clone git@github.com:nyelonong/agents.git ~/Projects/personal/agents
   ~/Projects/personal/agents/bootstrap.sh
   ```
   (needs the generated SSH key registered on GitHub first)
3. `claude login`

## Daily use

```sh
make switch              # apply config after editing (PROFILE=zaki default)
make update              # bump flake inputs, then apply
make fmt                 # format nix files
make help                # list all targets
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

- **Edit files in this repo, not in `~`.** Home versions are read-only
  symlinks into `/nix/store`, overwritten on every `make switch`.
- **New CLI tools go in `home.packages`** (`home.nix`), not brew. Language
  runtimes are the exception: [mise](https://mise.jdx.dev) owns them, pinned
  under `programs.mise.globalConfig.tools` in `home.nix`. To bump one, edit
  that, then `make switch && mise install`. Per-project overrides still work
  the usual way — drop a `mise.toml` or `.tool-versions` in the project.
- `~/.claude` is not tracked here except `statusline-command.sh`; Claude Code
  manages the rest per-machine.
