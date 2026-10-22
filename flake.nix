{
  description = "NixOS + Home Manager configuration running the MagikOS desktop";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager }:
    let
      magikosOverlay = final: prev: {
        magikos = final.callPackage ./nix/magikos.nix { };
      };

      magikosModule = ./nix/module.nix;
      homeModule = ./hosts/home.nix;

      # Home Manager for magikxiii, shared by every host. Wired in through
      # each NixOS host below so `nixos-rebuild switch` also activates it.
      #
      # The package is passed across explicitly rather than left to
      # `pkgs.magikos`: Home Manager's own `pkgs` argument does not inherit the
      # NixOS overlay set.
      hmFor = { modules ? [ ] }: {
        home-manager.users.magikxiii = {
          imports = [ homeModule ] ++ modules;
        };
      };

      # `{ config, ... }` cannot live inside `hmFor`'s attrset literal, so the
      # package hand-off is a separate module.
      hmPackage = { config, ... }: {
        home-manager.users.magikxiii.home-magikos.package = config.magikos.package;
      };
    in
    {
      nixosConfigurations.cachyos-x8664 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hardware-configuration.nix
          ./configuration.nix
          magikosModule
          home-manager.nixosModules.home-manager
          (hmFor { })
          hmPackage
          {
            nixpkgs.overlays = [ magikosOverlay ];
          }
        ];
      };

      # Disposable QEMU test VM: different disks, no EFI partition, no
      # bootloader, booted straight from the kernel/initrd. Shares the desktop
      # config and the dotfiles with the real machine.
      nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/vm.nix
          magikosModule
          home-manager.nixosModules.home-manager
          (hmFor { })
          hmPackage
          {
            nixpkgs.overlays = [ magikosOverlay ];
          }
        ];
      };

      # Bootable installer ISO. Layers the MagikOS desktop config on top of
      # the minimal installation CD, so a machine booted from it can run
      # `nixos-install --flake /iso/NixOSBuild#cachyos-x8664` (or any host)
      # and end up with the full MagikOS system. Build with:
      #   nix build .#nixosConfigurations.iso.config.system.build.isoImage
      nixosConfigurations.iso = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/iso.nix
          magikosModule
          home-manager.nixosModules.home-manager
          (hmFor { })
          hmPackage
          {
            nixpkgs.overlays = [ magikosOverlay ];
          }
        ];
      };

      # Standalone Home Manager, for `home-manager switch` on a non-NixOS host
      # or for iterating on dotfiles without a system rebuild.
      homeConfigurations."magikxiii@default" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux.extend magikosOverlay;
        modules = [ homeModule ];
      };
    };
}