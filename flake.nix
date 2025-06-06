{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.05";
    systems.url = "github:nix-systems/default-linux";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
  };

  outputs = { nixpkgs, flake-utils, self, ... }: let
    inherit (nixpkgs) lib;
  in {
    nixosModules = rec {
      default = sudo-run0;
      sudo-run0 = { config, pkgs, ... }: let
        this = self.packages.${pkgs.hostPlatform.system}.sudo-run0;
      in {
        config = lib.mkMerge [
          { security.sudo.enable = lib.mkDefault false; }

          (lib.mkIf (!config.security.sudo.enable) {
            environment.systemPackages = [ this ];

            # Really make sure Polkit is enabled. You don't want to be left
            # locked out of your system under any circumstance.
            security.polkit.enable = lib.mkForce true;
            assertions = lib.singleton {
              assertion = config.security.polkit.enable;
              message = "run0 requires Polkit but Polkit is disabled.";
            };

            # This has to be at least defined as `{}` due to NixOS/nixpkgs#361592.
            security.pam.services.systemd-run0 = lib.mkDefault {};
          })
        ];
      };
    };
  } // flake-utils.lib.eachDefaultSystem (system: let
    pkgs = nixpkgs.legacyPackages.${system};
    this = self.packages.${system}.sudo-run0;
  in {
    packages = rec {
      default = sudo-run0;
      sudo = sudo-run0;
      sudo-run0 = pkgs.writeShellApplication {
        name = "sudo";
        text = lib.removePrefix "#!/bin/bash\n" (builtins.readFile ./sudo-run0.sh);
      };
    };

    apps = rec {
      default = sudo-run0;
      sudo = sudo-run0;
      sudo-run0 = {
        type = "app";
        program = lib.getExe this;
      };
    };
  });
}
