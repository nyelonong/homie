{
  pkgs,
  lib,
  ...
}:
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
