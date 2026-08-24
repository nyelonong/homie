{ pkgs, lib, ... }:
let
  zedSettings =
    lib.recursiveUpdate (builtins.fromJSON (builtins.readFile ../config/zed/settings.json))
      {
        agent_servers.pi-acp = {
          default_config_options = {
            model = "litellm/azure_ai/gpt-5.6-terra";
            thought_level = "high";
          };
          type = "registry";
        };
      };
in
{
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

  programs.zsh.initContent = lib.mkAfter ''
    function pi-cekat() {
      local cli="''${CMUX_BUNDLED_CLI_PATH:-cmux}"
      command "$cli" set-status pi "litellm · azure_ai/gpt-5.6-terra" --icon sparkle --priority 90 >/dev/null 2>&1 || true
      command pi --provider litellm --model azure_ai/gpt-5.6-terra "$@"
      local rc=$?
      command "$cli" clear-status pi >/dev/null 2>&1 || true
      return $rc
    }
  '';
}
