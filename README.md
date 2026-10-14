# NixOSBuild

NixOS configuration generated from an existing CachyOS/MagikOS machine.

## Quick start (already on NixOS)

1. Clone:
   ```bash
   git clone git@github.com:ArchMagikXIII/NixOSBuild.git
   cd NixOSBuild
   ```
2. Review `configuration.nix` and `hardware-configuration.nix`:
   - user name/shell
   - timezone/locale
   - disk UUIDs/subvolumes
   - package list
3. Build and switch:
   ```bash
   sudo nixos-rebuild switch --flake .#cachyos-x8664
   ```

## Fresh NixOS install

1. Boot the NixOS ISO and install a minimal system.
2. Clone this repo into `/etc/nixos` (or any location).
3. Run the same rebuild command above.
4. Reboot.

## Notes

- Unfree packages are enabled (`allowUnfree = true`) for apps like Steam/Brave.
- This uses `nixos-unstable` and flakes; ensure flakes are enabled (`experimental-features = nix-command flakes`).
- Source-system (CachyOS/MagikOS) packages not available in nixpkgs were omitted. See `packages-arch.txt` for the original Arch package list.
- MagikOS/sway dotfiles are not managed by this repo yet.
