{ pkgs, config, ... }: {
  programs.zsh.shellAliases = {
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

  home.username = "zaki";
  home.homeDirectory = "/Users/zaki";

  home.packages = with pkgs; [
    # LLM
    apfel-llm
    hunk
    llmfit

    # Networking
    cloudflared

    # Secrets
    doppler
    infisical

    # macOS and PHP
    duti
    phpPackages.composer

    # Kubernetes and databases
    opentofu
    kubectl
    kubernetes-helm
    k9s
    mongosh
  ];

  home.file.".config/rex" = {
    source = ../config/rex;
    recursive = true;
    force = true;
  };

  home.sessionVariables = {
    "GEMINI_CLI_HOME" = "${config.home.homeDirectory}/.gemini";
    "CINETIC_PYTHON" = "${config.home.homeDirectory}/.venvs/cinetic/bin/python";
    "EARSHOT_PYTHON" = "${config.home.homeDirectory}/.local/share/earshot/.venv/bin/python";
  };
}
