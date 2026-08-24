{ pkgs, config, ... }:
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

      # cli tools
      eza
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
      "${config.home.homeDirectory}/Projects/go/bin"
      # Non-interactive shells do not receive mise's direct PATH activation.
      "${config.home.homeDirectory}/.local/share/mise/shims"
      "${config.home.homeDirectory}/.local/bin"
      "${config.home.homeDirectory}/.opencode/bin"
    ];

    # Replace app-created files at paths owned by the repository.
    file.".config" = {
      source = ../config;
      recursive = true;
      force = true;
    };
    file.".gitconfig" = {
      source = ../.gitconfig;
    };
  };

  xdg.enable = true;
  fonts.fontconfig.enable = true;
  programs.home-manager.enable = true;
}
