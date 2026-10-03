{ config, lib, ... }:
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
        k = "kubectl";
        kgp = "kubectl get pods";
        kgs = "kubectl get services";
        kgd = "kubectl get deployments";
        kgn = "kubectl get namespaces";
        kd = "kubectl describe";
        kl = "kubectl logs";
        klf = "kubectl logs -f";
        kex = "kubectl exec -it";
        kctx = "kubectl config use-context";
        kns = "kubectl config set-context --current --namespace";
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
