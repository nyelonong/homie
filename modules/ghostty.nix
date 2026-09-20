{ pkgs, lib, ... }:
{
  config = lib.mkIf pkgs.stdenv.isDarwin {
    home.file.".config/ghostty/config".source = ../config/ghostty/config;
  };
}
