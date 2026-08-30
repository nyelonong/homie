{
  pkgs,
  lib,
  ...
}:
{
  home = {
    packages = lib.optionals pkgs.stdenv.isDarwin [
      pkgs.skhd
      pkgs.sketchybar
    ];

    file.".skhdrc" = {
      source = ../.skhdrc;
    };

    file.".config/sketchybar/sketchybarrc" = {
      source = ../config/sketchybar/sketchybarrc;
      executable = true;
    };
    file.".config/sketchybar/plugins/omni_listener.sh" = {
      source = ../config/sketchybar/plugins/omni_listener.sh;
      executable = true;
    };
    file.".config/sketchybar/plugins/workspaces.sh" = {
      source = ../config/sketchybar/plugins/workspaces.sh;
      executable = true;
    };
    file.".config/sketchybar/plugins/ws_click.sh" = {
      source = ../config/sketchybar/plugins/ws_click.sh;
      executable = true;
    };
    file.".config/sketchybar/plugins/clock.sh" = {
      source = ../config/sketchybar/plugins/clock.sh;
      executable = true;
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
    sketchybar = {
      enable = true;
      config = {
        ProgramArguments = [ "${pkgs.sketchybar}/bin/sketchybar" ];
        KeepAlive = true;
        RunAtLoad = true;
        # Plugins resolve tools via these paths: launchd PATH has no nix
        # store or brew bin.
        EnvironmentVariables = {
          SKETCHYBAR_CLIENT = "${pkgs.sketchybar}/bin/sketchybar";
          JQ_BIN = "${pkgs.jq}/bin/jq";
          OMNIWMCTL_BIN = "/opt/homebrew/bin/omniwmctl";
        };
      };
    };
  };

  # OmniWM rewrites live settings on quit, so only seed a missing file or legacy symlink.
  home.activation.seedOmniWM = lib.mkIf pkgs.stdenv.isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      live="$HOME/.config/omniwm/settings.toml"
      if [ -L "$live" ]; then
        rm "$live"
        mkdir -p "$(dirname "$live")"
        install -m 0644 "${../apps/omniwm/settings.toml}" "$live"
      elif [ ! -f "$live" ]; then
        mkdir -p "$(dirname "$live")"
        install -m 0644 "${../apps/omniwm/settings.toml}" "$live"
      fi
    ''
  );

  # Apply keymap edits without waiting for the next login.
  home.activation.reloadSkhd = lib.mkIf pkgs.stdenv.isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.skhd}/bin/skhd -r || true
    ''
  );

  # Sketchybar only reads its config at startup, so restart it after a switch.
  home.activation.reloadSketchybar = lib.mkIf pkgs.stdenv.isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      /bin/launchctl kickstart -k "gui/$UID/org.nix-community.home.sketchybar" || true
    ''
  );
}
