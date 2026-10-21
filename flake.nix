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
      system = "x86_64-linux";

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

      # A build-time check on the packaged MagikOS tree.
      #
      # There is no other verification in this repo: `nix flake check` used to
      # evaluate cleanly while the package shipped seven scripts with a
      # #!/bin/bash shebang that could not execute, and while the config tree
      # baked in a store path that pointed at a stale build. Both are silent
      # failures at runtime -- a broken clipboard plugin, a suspend hook that
      # never runs -- so they are caught here instead.
      checks.${system}.magikos-package = let
        pkgs = nixpkgs.legacyPackages.${system};
        magikos = (pkgs.extend magikosOverlay).magikos;
      in
      pkgs.runCommand "magikos-package-check" { } ''
        tree="${magikos}/share/magikos"
        failed=0

        # 1. Every shebang in the tree must name an interpreter that exists.
        #    The package rewrites the ones on line 1 to absolute store paths;
        #    anything left pointing at /usr/bin/python3 cannot run on NixOS.
        #
        #    Scripts also embed shebangs in heredocs -- magikos-mise-install
        #    writes a wrapper into ~/.local/bin that way -- so every line
        #    that starts with "#!" is checked, not just the first.
        #
        #    /bin/bash and /bin/sh are the exception: NixOS does not provide
        #    them, but the configuration creates /bin/bash through
        #    system.activationScripts.binbash, so a script that relies on
        #    them does run here.
        while IFS= read -r f; do
          while IFS= read -r interp; do
            interp=''${interp#\#!}
            interp=''${interp%% *}
            case "$interp" in
              /bin/bash|/bin/sh)
                ;;
              /*)
                if [ ! -x "$interp" ]; then
                  echo "shebang interpreter does not exist: $f -> $interp" >&2
                  failed=1
                fi
                ;;
            esac
          done < <(grep -h '^#!' "$f" || true)
        done < <(find "$tree" -type f ! -name '*.md' -print0 | xargs -0 -r grep -lI '^#!')

        # 2. Every wrapper must exec a script that is actually there, and
        #    that script has to be executable -- a wrapper around a
        #    non-executable file dies with "Permission denied".
        for w in "${magikos}"/bin/*; do
          target=$(sed -n 's|^exec "\(.*\)" "\$@"$|\1|p' "$w")
          [ -n "$target" ] || continue
          if [ ! -f "$target" ]; then
            echo "wrapper points at a missing script: $w -> $target" >&2
            failed=1
          elif [ ! -x "$target" ]; then
            echo "wrapper points at a non-executable script: $w -> $target" >&2
            failed=1
          fi
        done

        # 3. The config tree must not bake in a store path. Those references
        #    are copied into ~/.config, where a store path goes stale -- or
        #    gets garbage collected -- as soon as the package is rebuilt.
        #    Shebangs are exempt: they are rewritten to an absolute interpreter
        #    on purpose, and have to stay that way to be executable.
        stale=$(grep -rIn -e "${builtins.storeDir}" "$tree/config" 2>/dev/null | grep -v ':[0-9]*:#!' || true)
        if [ -n "$stale" ]; then
          echo "config tree references a store path; it will go stale" >&2
          echo "$stale" >&2
          failed=1
        fi

        # 4. Nothing may still name the Arch install root, which does not
        #    exist here.
        if grep -rIl "/usr/share/magikos" "$tree" >/dev/null 2>&1; then
          echo "tree still references the Arch install root /usr/share/magikos" >&2
          failed=1
        fi

        if [ "$failed" -ne 0 ]; then
          exit 1
        fi
        echo "magikos package check passed"
        touch $out
      '';
    };
}