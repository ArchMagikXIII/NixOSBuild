{
  description = "NixOS configuration generated from the current CachyOS/MagikOS system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    nixosConfigurations.cachyos-x8664 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hardware-configuration.nix
        ./configuration.nix
      ];
    };

    # Disposable QEMU test VM: different disks, no EFI partition, no bootloader.
    # Shares the desktop config with the real machine but has its own hardware.
    nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hosts/vm.nix
      ];
    };
  };
}
