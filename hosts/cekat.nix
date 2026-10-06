{ ... }:
{
  imports = [ ./personal.nix ];

  home.sessionVariables = {
    # go modules from the org are private: skip the proxy and checksum db
    GOPRIVATE = "github.com/cekataiofficial/*";
    GONOSUMDB = "github.com/cekataiofficial/*";
  };
}
