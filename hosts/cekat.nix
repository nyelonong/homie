{
  pkgs,
  lib,
  ...
}:
let
  zedSettings = lib.recursiveUpdate (builtins.fromJSON (builtins.readFile ../apps/zed/settings.json)) (
    builtins.fromJSON (builtins.readFile ../apps/zed/cekat-overlay.json)
  );
  zedCekatSeed = builtins.toFile "zed-cekat-settings.json" (builtins.toJSON zedSettings);
in
{
  home.username = "zaki";
  home.homeDirectory = "/Users/zaki";

  home.packages = with pkgs; [
    opentofu
    kubectl
    k9s
    mongosh
  ];

  home.sessionVariables = {
    # go modules from the org are private: skip the proxy and checksum db
    GOPRIVATE = "github.com/cekataiofficial/*";
    GONOSUMDB = "github.com/cekataiofficial/*";
  };

  home.activation.seedCekatZed = lib.hm.dag.entryBetween [ "seedZed" ] [ "writeBoundary" ] ''
    live="$HOME/.config/zed/settings.json"
    if [ -L "$live" ]; then
      rm "$live"
    fi
    if [ ! -f "$live" ]; then
      mkdir -p "$(dirname "$live")"
      install -m 0644 "${zedCekatSeed}" "$live"
    fi
  '';
}
