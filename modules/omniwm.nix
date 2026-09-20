{ pkgs, lib, ... }:
let
  omniwmDisplayRouting = pkgs.writeShellScript "omniwm-display-routing" (
    builtins.readFile ../scripts/omniwm-display-routing
  );
in
{
  config = lib.mkIf pkgs.stdenv.isDarwin {
    launchd.agents.omniwmDisplayRouting = {
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

    # OmniWM rewrites live settings on quit, so only seed a missing file or legacy symlink.
    home.activation.seedOmniWM = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      live="$HOME/.config/omniwm/settings.toml"
      if [ -L "$live" ]; then
        rm "$live"
        mkdir -p "$(dirname "$live")"
        install -m 0644 "${../apps/omniwm/settings.toml}" "$live"
      elif [ ! -f "$live" ]; then
        mkdir -p "$(dirname "$live")"
        install -m 0644 "${../apps/omniwm/settings.toml}" "$live"
      fi
    '';
  };
}
