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

      # pi-* wrappers stamp the provider and model on the cmux workspace tab.
      initContent = lib.mkAfter ''
        if [ -r "${config.home.homeDirectory}/.zshrc.local" ]; then
          source "${config.home.homeDirectory}/.zshrc.local"
        fi

        function pi-cekat() {
          local cli="''${CMUX_BUNDLED_CLI_PATH:-cmux}"
          command "$cli" set-status pi "litellm · azure_ai/gpt-5.6-terra" --icon sparkle --priority 90 >/dev/null 2>&1 || true
          command pi --provider litellm --model azure_ai/gpt-5.6-terra "$@"
          local rc=$?
          command "$cli" clear-status pi >/dev/null 2>&1 || true
          return $rc
        }
        function pi-codex() {
          local cli="''${CMUX_BUNDLED_CLI_PATH:-cmux}"
          command "$cli" set-status pi "openai-codex · gpt-5.6-terra" --icon sparkle --priority 90 >/dev/null 2>&1 || true
          command pi --provider openai-codex --model gpt-5.6-terra "$@"
          local rc=$?
          command "$cli" clear-status pi >/dev/null 2>&1 || true
          return $rc
        }
        function pi-opencode() {
          local cli="''${CMUX_BUNDLED_CLI_PATH:-cmux}"
          command "$cli" set-status pi "opencode-go · mimo-v2.5" --icon sparkle --priority 90 >/dev/null 2>&1 || true
          command pi --provider opencode-go --model mimo-v2.5 "$@"
          local rc=$?
          command "$cli" clear-status pi >/dev/null 2>&1 || true
          return $rc
        }
        function pi-openrouter() {
          local cli="''${CMUX_BUNDLED_CLI_PATH:-cmux}"
          command "$cli" set-status pi "openrouter · z-ai/glm-5.2" --icon sparkle --priority 90 >/dev/null 2>&1 || true
          command pi --provider openrouter --model z-ai/glm-5.2 "$@"
          local rc=$?
          command "$cli" clear-status pi >/dev/null 2>&1 || true
          return $rc
        }
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
