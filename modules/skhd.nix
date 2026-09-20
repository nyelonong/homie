{ pkgs, lib, ... }:
{
  config = lib.mkIf pkgs.stdenv.isDarwin {
    home = {
      packages = [ pkgs.skhd ];

      file.".skhdrc".source = ../.skhdrc;

      activation.reloadSkhd = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${pkgs.skhd}/bin/skhd -r || true
      '';
    };

    launchd.agents.skhd = {
      enable = true;
      config = {
        ProgramArguments = [ "${pkgs.skhd}/bin/skhd" ];
        KeepAlive = true;
        RunAtLoad = true;
      };
    };
  };
}
