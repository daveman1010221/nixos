{
  inputs = {
    nixpkgs.follows = "nixos-cosmic/nixpkgs";

    nixos-cosmic.url = "github:lilyinstarlight/nixos-cosmic";

    rust-overlay.url = "github:oxalica/rust-overlay?rev=260ff391290a2b23958d04db0d3e7015c8417401";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.inputs.flake-utils.url = "github:numtide/flake-utils";

    myNeovimOverlay.url = "github:daveman1010221/nix-neovim";
    myNeovimOverlay.inputs.nixpkgs.follows = "nixpkgs";
    myNeovimOverlay.inputs.flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixos-cosmic, rust-overlay, myNeovimOverlay, ... }@inputs:
  let
    system = "x86_64-linux";
    overlays = [
      rust-overlay.overlays.default
      myNeovimOverlay.overlays.default
    ];

    pkgs = import nixpkgs {
      inherit system;
      overlays = overlays;
      config = {
        allowUnfree = true;
        nvidia = {
          acceptLicense = true;
        };
      };
    };
  in {
    nixosConfigurations = {
      precisionws = nixpkgs.lib.nixosSystem {
        inherit system pkgs;

        modules = [
          {
            nix.settings = {
              substituters = [ "https://cosmic.cachix.org/" ];
              trusted-public-keys = [ "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE=" ];
            };
          }

          # Wrap the function in parentheses
          ({ pkgs, ... }: {
            environment.systemPackages = with pkgs; [
              rust-bin.stable.latest.default
              nvim-pkg
            ];
          })

          # Additional modules
          nixos-cosmic.nixosModules.default
          ./configuration.nix
        ];
      };
    };
  };
}
