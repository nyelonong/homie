{ config, lib, ... }:
{
  programs = {
    zsh = {
      enable = true;
      autosuggestion.enable = true;

      shellAliases = {
        cat = "bat";
        ls = "eza --icons --group-directories-first";
        ll = "eza --icons --group-directories-first -lah";
        tree = "ll --tree";
        st = "git status";
        dif = "git diff";
      };

      initContent = lib.mkAfter ''
        if [ -r "${config.home.homeDirectory}/.zshrc.local" ]; then
          source "${config.home.homeDirectory}/.zshrc.local"
        fi
      '';
    };

    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
    };

    starship = {
      enable = true;
      enableZshIntegration = true;
    };
  };
}
