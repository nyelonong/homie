{ pkgs, lib, ... }:
{
  config = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    # The live Ghostty config stays app-editable, so only seed a missing file or legacy symlink.
    home.activation.seedGhostty = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      live="$HOME/.config/ghostty/config"
      if [ -L "$live" ]; then
        rm "$live"
        mkdir -p "$(dirname "$live")"
        install -m 0644 "${../apps/ghostty/config}" "$live"
      elif [ ! -f "$live" ]; then
        mkdir -p "$(dirname "$live")"
        install -m 0644 "${../apps/ghostty/config}" "$live"
      fi
    '';
  };
}
