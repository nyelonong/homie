{ pkgs, ... }: {
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
  };
}
