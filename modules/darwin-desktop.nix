{
  pkgs,
  lib,
  ...
}:
let
  omniwmDisplayRouting = pkgs.writeShellScript "omniwm-display-routing" (
    builtins.readFile ../scripts/omniwm-display-routing
  );
in
{
  home = {
    packages = lib.optionals pkgs.stdenv.isDarwin [ pkgs.skhd ];

    file.".skhdrc" = {
      source = ../.skhdrc;
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

    # OmniWM only supports static workspace monitor assignments. Its display-change
    # subscription lets this handler apply the one monitor-specific exception.
    omniwmDisplayRouting = {
      enable = true;
      config = {
        ProgramArguments = [
          "/Applications/OmniWM.app/Contents/MacOS/omniwmctl"
          "watch"
          "display-changed"
          "--exec"
          "${omniwmDisplayRouting}"
        ];
        KeepAlive = true;
        RunAtLoad = true;
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
}
