{ pkgs, ... }:
{
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
    opentofu
    kubectl
    k9s
    mongosh
  ];

  home.sessionVariables = {
    # go modules from the org are private: skip the proxy and checksum db
    GOPRIVATE = "github.com/cekataiofficial/*";
    GONOSUMDB = "github.com/cekataiofficial/*";
  };

}
