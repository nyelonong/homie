{
  pkgs,
  lib,
  ...
}:
let
  zedSettings =
    lib.recursiveUpdate (builtins.fromJSON (builtins.readFile ../config/zed/settings.json))
      {
        agent_servers.pi-acp = {
          default_config_options = {
            model = "litellm/azure_ai/gpt-5.6-luna";
            thought_level = "medium";
          };
          type = "registry";
        };
      };
in
{
  programs.zsh.shellAliases.pi-cekat = "PI_CODING_AGENT_DIR=$HOME/.pi/agent-cekat pi";

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

  home.file.".config/zed/settings.json".text = lib.mkForce (builtins.toJSON zedSettings);

}
