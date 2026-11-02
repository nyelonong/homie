{ pkgs, lib, ... }:
{
  config = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    targets.darwin.defaults = {
      NSGlobalDomain = {
        AppleInterfaceStyle = "Dark";
        _HIHideMenuBar = false;
      };
      "com.apple.dock".autohide = true;
      "com.apple.menuextra.clock" = {
        ShowDate = 1;
        ShowDayOfWeek = true;
      };
    };

    # 18 shows the Bluetooth icon in the menu bar; 8 keeps it in Control Center only.
    targets.darwin.currentHostDefaults."com.apple.controlcenter".Bluetooth = 18;
  };
}
