{
  description = "home sweet home";

  # inputs are other flakes you use within your own flake, dependencies
  # if you will
  inputs = {
    # unstable has the 'freshest' packages you will find, even the AUR
    # doesn't do as good as this, and it's all precompiled.
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # In this context, outputs are mostly about getting home-manager what it
  # needs since it will be the one using the flake
  outputs =
    { nixpkgs, home-manager, ... }:
    let
      mkHome =
        system: extra:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          modules = [ ./home.nix ] ++ extra;
        };
    in
    {
      homeConfigurations = {
        "zaki" = mkHome "aarch64-darwin" [ ./hosts/personal.nix ]; # personal mac
        "zaki@windows" = mkHome "x86_64-linux" [ ./hosts/windows.nix ]; # WSL2 on Windows
      };
    };
}
