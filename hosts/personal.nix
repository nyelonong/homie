{ pkgs, config, ... }: {
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
  ];

  home.sessionVariables = {
    "GEMINI_CLI_HOME" = "${config.home.homeDirectory}/.gemini";
  };
}
