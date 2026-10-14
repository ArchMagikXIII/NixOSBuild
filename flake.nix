{
  description = "NixOS configuration generated from the current CachyOS/MagikOS system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      magikosOverlay = final: prev: {
        magikos = final.callPackage ./nix/magikos.nix { };
      };
      magikosModule = ./nix/module.nix;
    in
    {
      nixosConfigurations.cachyos-x8664 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hardware-configuration.nix
          ./configuration.nix
          magikosModule
          {
            nixpkgs.overlays = [ magikosOverlay ];
          }
        ];
      };

      # Disposable QEMU test VM: different disks, no EFI partition, no bootloader.
      # Shares the desktop config with the real machine but has its own hardware.
      nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/vm.nix
          magikosModule
          {
            nixpkgs.overlays = [ magikosOverlay ];
          }
        ];
      };
    };
}
