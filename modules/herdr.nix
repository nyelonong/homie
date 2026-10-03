{ pkgs, lib, ... }:
{
  config = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    home.packages = [ pkgs.herdr ];

    # The live Herdr config stays app-editable, so only seed a missing file or legacy symlink.
    home.activation.seedHerdr = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      live="$HOME/.config/herdr/config.toml"
      if [ -L "$live" ]; then
        rm "$live"
        mkdir -p "$(dirname "$live")"
        install -m 0644 "${../apps/herdr/config.toml}" "$live"
      elif [ ! -f "$live" ]; then
        mkdir -p "$(dirname "$live")"
        install -m 0644 "${../apps/herdr/config.toml}" "$live"
      fi
    '';
  };
}
