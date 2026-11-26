{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs = {
    zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      shellAliases = {
        cat = "bat";
        ls = "eza --icons --group-directories-first";
        ll = "eza --icons --group-directories-first -lah";
        tree = "ll --tree";
        st = "git status";
        dif = "git diff";
        nq = "nu -c";
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        cb = "git branch --show-current | tr -d '\\n' | pbcopy";
      };

      # Terminals send Ctrl-U for Cmd-Backspace; zsh's default kill-whole-line also deletes
      # right of the cursor, unlike macOS.
      initContent = lib.mkAfter ''
        bindkey '^U' backward-kill-line
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
