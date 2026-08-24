{
  pkgs,
  config,
  lib,
  ...
}:
{
  home = {
    stateVersion = "26.05";
    # username + homeDirectory are per-machine; see ./hosts/*.nix

    packages =
      with pkgs;
      [
        # vcs (delta: git pager, wired in .gitconfig)
        git
        gh
        delta

        # lang / versioning (runtime versions: see programs.mise below)
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
      ]
      # mac desktop layer (better-mac exploration) — Linux profiles must not see these
      ++ lib.optionals pkgs.stdenv.isDarwin [
        skhd
      ];

    sessionVariables = {
      GOPATH = "${config.home.homeDirectory}/Projects/go";
      GOBIN = "${config.home.homeDirectory}/Projects/go/bin";

      NIXPKGS_ALLOW_UNFREE = "1";
    };

    sessionPath = [
      "${config.home.homeDirectory}/Projects/go/bin"
      # mise shims: interactive zsh gets real binaries via programs.mise's PATH
      # activation, but non-interactive shells (editors, hooks, launchd) never
      # source it — they need the shims to see node/go/python.
      "${config.home.homeDirectory}/.local/share/mise/shims"
      "${config.home.homeDirectory}/.local/bin"
      "${config.home.homeDirectory}/.opencode/bin"
    ];

    # force: any stray real file an app drops where our config tree symlinks
    # gets replaced by the repo copy on every switch
    file.".config" = {
      source = ./config;
      recursive = true;
      force = true;
    };
    file.".gitconfig" = {
      source = ./.gitconfig;
    };

    file.".skhdrc" = {
      source = ./config/skhd/skhdrc;
    };
  };

  launchd.agents = lib.mkIf pkgs.stdenv.isDarwin {
    skhd = {
      enable = true;
      config = {
        ProgramArguments = [ "${pkgs.skhd}/bin/skhd" ];
        KeepAlive = true;
        RunAtLoad = true;
      };
    };
  };

  xdg.enable = true;
  fonts.fontconfig.enable = true;

  # OmniWM owns its live settings file — it rewrites it on every quit, so a
  # symlink from the repo just breaks. The repo copy is a seed: installed when
  # missing (or when the live file is still one of our old symlinks), then the
  # GUI wins until `make omniwm-harvest` pulls changes back into the repo.
  home.activation.seedOmniWM = lib.mkIf pkgs.stdenv.isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      live="$HOME/.config/omniwm/settings.toml"
      if [ -L "$live" ]; then
        rm "$live"
        mkdir -p "$(dirname "$live")"
        install -m 0644 "${./apps/omniwm/settings.toml}" "$live"
      elif [ ! -f "$live" ]; then
        mkdir -p "$(dirname "$live")"
        install -m 0644 "${./apps/omniwm/settings.toml}" "$live"
      fi
    ''
  );

  # Reload skhd after every switch so .skhdrc edits land immediately;
  # harmless no-op when skhd isn't running (fresh boot: RunAtLoad starts it).
  home.activation.reloadSkhd = lib.mkIf pkgs.stdenv.isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.skhd}/bin/skhd -r || true
    ''
  );

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
        pnpm = "11.22.0";
        python = "3.13.15";
        rust = "1.97.1";
        uv = "0.11.32";
        bun = "1.3.14";
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

      # pi-* wrappers stamp the provider/model pill on the cmux workspace tab;
      # outside cmux the cmux calls fail silently and pi just runs normally.
      initContent = lib.mkAfter ''
        if [ -r "${config.home.homeDirectory}/.zshrc.local" ]; then
          source "${config.home.homeDirectory}/.zshrc.local"
        fi

        function pi-cekat() {
          local cli="''${CMUX_BUNDLED_CLI_PATH:-cmux}"
          command "$cli" set-status pi "litellm · azure_ai/gpt-5.6-terra" --icon sparkle --priority 90 >/dev/null 2>&1 || true
          command pi --provider litellm --model azure_ai/gpt-5.6-terra "$@"
          local rc=$?
          command "$cli" clear-status pi >/dev/null 2>&1 || true
          return $rc
        }
        function pi-codex() {
          local cli="''${CMUX_BUNDLED_CLI_PATH:-cmux}"
          command "$cli" set-status pi "openai-codex · gpt-5.6-terra" --icon sparkle --priority 90 >/dev/null 2>&1 || true
          command pi --provider openai-codex --model gpt-5.6-terra "$@"
          local rc=$?
          command "$cli" clear-status pi >/dev/null 2>&1 || true
          return $rc
        }
        function pi-opencode() {
          local cli="''${CMUX_BUNDLED_CLI_PATH:-cmux}"
          command "$cli" set-status pi "opencode-go · mimo-v2.5" --icon sparkle --priority 90 >/dev/null 2>&1 || true
          command pi --provider opencode-go --model mimo-v2.5 "$@"
          local rc=$?
          command "$cli" clear-status pi >/dev/null 2>&1 || true
          return $rc
        }
        function pi-openrouter() {
          local cli="''${CMUX_BUNDLED_CLI_PATH:-cmux}"
          command "$cli" set-status pi "openrouter · z-ai/glm-5.2" --icon sparkle --priority 90 >/dev/null 2>&1 || true
          command pi --provider openrouter --model z-ai/glm-5.2 "$@"
          local rc=$?
          command "$cli" clear-status pi >/dev/null 2>&1 || true
          return $rc
        }
      '';

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
