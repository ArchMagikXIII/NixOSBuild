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

## Hosts

This flake exposes two hosts. They share `configuration.nix` (desktop, packages,
services) but have completely separate hardware profiles.

| Host | Profile | Disk layout | Bootloader |
|---|---|---|---|
| `cachyos-x8664` | `hardware-configuration.nix` | btrfs subvolumes, separate vfat `/boot` | systemd-boot (UEFI) |
| `vm` | `hosts/vm.nix` | single ext4 `/`, no `/boot` | none — booted via QEMU `-kernel`/`-initrd` |

Build them by suffix:

```bash
sudo nixos-rebuild switch --flake .#cachyos-x8664   # real machine
sudo nixos-rebuild switch --flake .#vm              # QEMU test VM
```

The `vm` host is a disposable QEMU guest: it has no EFI system partition, so
*no* bootloader is installed. It also autologins into Sway, since
`configuration.nix` intentionally sets no user password. Recreate it from the
QEMU command line with:

```bash
-kernel /nix/store/*-nixos-system-vm-*/kernel-modules/lib/modules/*/vmlinuz \
-initrd /nix/store/*-nixos-system-vm-*/initrd \
-append "init=/nix/store/*-nixos-system-vm-*/init" \
-drive file=vm.qcow2,if=virtio
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
- **Login/password:** `users.users.magikxiii` in `configuration.nix` sets no password. On an existing install the
  current password is preserved, but on a *fresh* install the account is created locked. Set one with
  `sudo passwd magikxiii` (or add `hashedPassword`/`initialPassword` locally) or you will not be able to log in.
