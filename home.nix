{
  pkgs,
  config,
  ...
}:
{
  home = {
    stateVersion = "26.05";
    # username + homeDirectory are per-machine; see ./hosts/*.nix

    packages = with pkgs; [
      # vcs (delta: git pager, wired in .gitconfig)
      git
      gh
      delta

      # lang / versioning (runtime versions: see programs.mise below)
      nixfmt
      nil
      pnpm

      # cli tools (jq: needed by .claude/statusline-command.sh)
      eza
      bat
      fd
      ripgrep
      jq
      tealdeer
      ntfy-sh

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
      # mise shims: interactive zsh gets real binaries via programs.mise's PATH
      # activation, but non-interactive shells (Claude Code hooks, editors,
      # launchd) never source it — they need the shims to see node/go/python.
      "${config.home.homeDirectory}/.local/share/mise/shims"
      "${config.home.homeDirectory}/.local/bin"
      "${config.home.homeDirectory}/.opencode/bin"
    ];

    file.".config" = {
      source = ./config;
      recursive = true;
    };
    file.".zshrc" = {
      source = ./.zshrc;
    };
    file.".gitconfig" = {
      source = ./.gitconfig;
    };

    # Claude Code: only the statusline script is managed declaratively.
    file.".claude/statusline-command.sh" = {
      source = ./.claude/statusline-command.sh;
      executable = true;
    };
  };

  # ntfy subscriber: fires a macOS notification per message. Token lives in
  # ~/.config/ntfy/token.env (untracked, not this repo) as NTFY_TOKEN=tk_...
  # Flip enable to true and set the real topic once that file exists, then
  # `home-manager switch`.
  launchd.agents.ntfy-subscribe = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/zsh"
        "${config.home.homeDirectory}/.config/ntfy/subscribe-notify.sh"
        "zaki-alarm"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      EnvironmentVariables = {
        PATH = "${pkgs.ntfy-sh}/bin:/usr/bin:/bin";
      };
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/ntfy-subscribe.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/ntfy-subscribe.log";
    };
  };

  xdg.enable = true;
  fonts.fontconfig.enable = true;

  programs = {
    home-manager.enable = true;

    direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    # Language runtimes — pinned here, materialized by `mise install`
    # (bootstrap.sh runs it; mise also auto-installs a missing tool on first
    # use). Deliberately not in home.packages: runtimes need per-project
    # overrides via a repo's own mise.toml / .tool-versions.
    mise = {
      enable = true;
      enableZshIntegration = true;

      globalConfig.tools = {
        go = "1.26.5";
        node = "26.5.0";
        python = "3.13";
      };
    };

    zsh = {
      enable = true;
      autosuggestion.enable = true;

      shellAliases = {
        cat = "bat";
        ls = "eza --icons --group-directories-first";
        ll = "eza --icons --group-directories-first -lah";
        tree = "ll --tree";
        st = "git status";
        dif = "git diff";
      };

    };

    # replaces autojump (unmaintained): `z <dir>` jumps, `zi` picks via fzf
    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };

    # Ctrl-T (files) and Alt-C (cd) stay on fzf; Ctrl-R is atuin's (below) —
    # historyWidget disabled here so the two integrations stop fighting over it.
    fzf = {
      enable = true;
      enableZshIntegration = true;
      historyWidget.zsh.command = "";
    };

    # SQLite-backed shell history: fuzzy search, survives across sessions
    atuin = {
      enable = true;
      enableZshIntegration = true;
      flags = [ "--disable-up-arrow" ];
    };

    starship = {
      enable = true;
      enableZshIntegration = true;
    };
  };
}
