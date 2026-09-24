{
  pkgs,
  config,
  lib,
  ...
}:
{
  home = {
    stateVersion = "26.05";

    packages = with pkgs; [
      # vcs (delta: git pager, wired in .gitconfig)
      git
      gh
      delta

      # lang / versioning (runtime versions: see programs.mise)
      nixfmt
      nil
      gopls
      shfmt
      taplo
      marksman
      bash-language-server
      typescript-language-server
      vscode-langservers-extracted
      prettier

      # cli tools
      eza
      # Only coreutils' timeout: the full package would shadow BSD ls/date/stat.
      (runCommand "coreutils-timeout" { } ''
        mkdir -p $out/bin
        ln -s ${coreutils}/bin/timeout $out/bin/timeout
      '')
      bat
      fd
      ripgrep
      jq
      tealdeer

      # fonts
      pkgs.nerd-fonts.fira-code
      pkgs.nerd-fonts.droid-sans-mono
      pkgs.nerd-fonts.hack
    ];

    sessionVariables = {
      GOPATH = "${config.home.homeDirectory}/Projects/go";
      GOBIN = "${config.home.homeDirectory}/Projects/go/bin";

      NIXPKGS_ALLOW_UNFREE = "1";
    };

    sessionPath = [
      "${config.home.homeDirectory}/.cache/.bun/bin"
      "${config.home.homeDirectory}/Projects/go/bin"
      # Non-interactive shells do not receive mise's direct PATH activation.
      "${config.home.homeDirectory}/.local/share/mise/shims"
      "${config.home.homeDirectory}/.local/bin"
      "${config.home.homeDirectory}/.opencode/bin"
    ];

    # Replace app-created files at paths owned by the repository.
    file = {
      ".config/starship.toml" = {
        source = ../config/starship.toml;
        force = true;
      };
      ".config/helix/config.toml" = {
        source = ../config/helix/config.toml;
        force = true;
      };
      ".config/helix/languages.toml" = {
        source = ../config/helix/languages.toml;
        force = true;
      };
      ".config/zed/keymap.json" = {
        text = builtins.readFile ../config/zed/keymap.json;
        force = true;
      };
      ".gitconfig" = {
        source = ../.gitconfig;
      };
    };
  };

  home.activation.seedZed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    live="$HOME/.config/zed/settings.json"
    if [ -L "$live" ]; then
      rm "$live"
    fi
    if [ ! -f "$live" ]; then
      mkdir -p "$(dirname "$live")"
      install -m 0644 "${../apps/zed/settings.json}" "$live"
    fi
  '';

  xdg.enable = true;
  fonts.fontconfig.enable = true;
  programs.home-manager.enable = true;
}
