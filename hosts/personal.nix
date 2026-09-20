{ pkgs, config, ... }: {
  home.username = "zaki";
  home.homeDirectory = "/Users/zaki";

  home.packages = with pkgs; [
    # LLM
    apfel-llm

    # Networking
    cloudflared
  ];

  home.sessionVariables = {
    "GEMINI_CLI_HOME" = "${config.home.homeDirectory}/.gemini";
  };
}
