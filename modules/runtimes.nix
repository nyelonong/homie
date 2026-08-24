{ ... }:
{
  programs = {
    direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    # mise owns runtime pins so projects can override them independently of Nix packages.
    mise = {
      enable = true;
      enableZshIntegration = true;

      globalConfig.tools = {
        go = "1.26.5";
        node = "26.5.0";
        pnpm = "11.22.0";
        python = "3.13.15";
        rust = "1.97.1";
        uv = "0.11.32";
        bun = "1.3.14";
      };
    };
  };
}
