{
  description = "Foundry - my public NixOS/home-manager infrastructure monorepo";

  nixConfig = {
    extra-substituters = [
      "https://cache.m7.rs"
    ];
    extra-trusted-public-keys = [
      "cache.m7.rs:kszZ/NSwE/TjhOcPPQ16IuUiuRSisdiIwhKZCxguaWg="
    ];
  };

  inputs = {
    # Nix ecosystem
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default-linux";

    hardware = {
      url = "github:nixos/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    system-manager = {
      url = "github:numtide/system-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-system-graphics = {
      url = "github:soupglasses/nix-system-graphics";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-mailserver = {
      url = "gitlab:simple-nixos-mailserver/nixos-mailserver";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-minecraft = {
      url = "github:infinidoge/nix-minecraft";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Third party programs, packaged with nix
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hytale = {
      url = "github:TNAZEP/HytaleLauncherFlake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    system-manager,
    systems,
    ...
  } @ inputs: let
    inherit (self) outputs;
    lib = let
      base = nixpkgs.lib // home-manager.lib;
    in
      base
      // {
        colors = import ./lib/colors.nix {lib = base;};
        material-you = import ./lib/material-you.nix {lib = base;};
      };
    forEachSystem = f: lib.genAttrs (import systems) (system: f pkgsFor.${system});
    pkgsFor = lib.genAttrs (import systems) (
      system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        }
    );
  in {
    inherit lib;
    nixosModules = import ./modules/nixos;
    homeManagerModules = import ./modules/home-manager;

    overlays = import ./overlays {inherit inputs outputs;};
    hydraJobs = import ./hydra.nix {inherit inputs outputs;};

    packages = forEachSystem (pkgs: import ./pkgs {inherit pkgs;});
    devShells = forEachSystem (pkgs: import ./shell.nix {inherit pkgs;});
    formatter = forEachSystem (pkgs: pkgs.alejandra);

    nixosConfigurations = {
      # Main desktop
      atlas = lib.nixosSystem {
        modules = [./hosts/nixos/atlas];
        specialArgs = {
          inherit inputs outputs;
        };
      };
      # Living room desktop
      pleione = lib.nixosSystem {
        modules = [./hosts/nixos/pleione];
        specialArgs = {
          inherit inputs outputs;
        };
      };
      # Personal laptop (Framework 13)
      maia = lib.nixosSystem {
        modules = [./hosts/nixos/maia];
        specialArgs = {
          inherit inputs outputs;
        };
      };
      # Core server (Vultr)
      alcyone = lib.nixosSystem {
        modules = [./hosts/nixos/alcyone];
        specialArgs = {
          inherit inputs outputs;
        };
      };
      # Build and game server (Oracle)
      celaeno = lib.nixosSystem {
        modules = [./hosts/nixos/celaeno];
        specialArgs = {
          inherit inputs outputs;
        };
      };
      # Build and game server (Magalu Cloud)
      taygeta = lib.nixosSystem {
        modules = [./hosts/nixos/taygeta];
        specialArgs = {
          inherit inputs outputs;
        };
      };
      # Media server (RPi)
      merope = lib.nixosSystem {
        modules = [./hosts/nixos/merope];
        specialArgs = {
          inherit inputs outputs;
        };
      };
    };

    systemConfigs.mgc = system-manager.lib.makeSystemConfig {
      modules = [./hosts/system-manager/mgc];
      overlays = builtins.attrValues outputs.overlays;
      specialArgs = {
        inherit inputs outputs;
      };
    };

    homeConfigurations = {};
  };
}
