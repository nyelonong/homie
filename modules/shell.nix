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

    # Atuin owns Ctrl-R while fzf keeps its file and directory widgets.
    fzf = {
      enable = true;
      enableZshIntegration = true;
      historyWidget.zsh.command = "";
    };

    atuin = {
      enable = true;
      enableZshIntegration = true;
      flags = [ "--disable-up-arrow" ];
    };

    starship = {
      enable = true;
      enableZshIntegration = true;
    };
  };
}
