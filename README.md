# NixOSBuild

NixOS + Home Manager configuration running **MagikOS** (Sway + QuickShell shell),
ported from an existing CachyOS/MagikOS machine.

## What this repo contains

| Path | Purpose |
|---|---|
| `flake.nix` | Two NixOS hosts + a standalone Home Manager config |
| `nix/magikos.nix` | Packages MagikOS from the upstream git repo into the store |
| `nix/module.nix` | NixOS integration: systemd user units, sudo rules, `MAGIKOS_PATH` |
| `hosts/home.nix` | Home Manager dotfiles, sourced from the packaged config tree |
| `hosts/vm.nix` | QEMU test-VM hardware profile |
| `hardware-configuration.nix` | Real-machine disks (btrfs subvolumes, UEFI `/boot`) |
| `configuration.nix` | Shared desktop: packages, Sway, PipeWire, SDDM |

## The MagikOS package

MagikOS ships as `/usr/share/magikos` on Arch. Nix has no such prefix, so
`nix/magikos.nix` installs the tree to `$out/share/magikos` and handles four
things the Arch packaging got for free:

1. **Shebangs.** 404 scripts use `#!/bin/bash` and 2 use `#!/usr/bin/python3`;
   neither path exists in a Nix closure, so both are rewritten to store paths.
2. **`/usr/share/magikos`.** 112 files reference it. The 65 that go through
   `${MAGIKOS_PATH:-...}` are covered by the wrappers exporting `MAGIKOS_PATH`;
   the rest are rewritten at build time.
3. **`/usr/bin/<tool>`.** `quickshell`, `uwsm-app` and `xdg-terminal-exec` are
   hardcoded by the autostart line and two in-tree shims. On NixOS these live on
   `PATH`, so the leading `/usr/bin` is stripped.
4. **PATH.** Each of the ~417 scripts gets a wrapper exporting `MAGIKOS_PATH`
   plus a 47-package runtime closure, so it works when invoked from sway `exec`
   lines, QuickShell `Process` calls, or systemd units rather than a login shell.

`iso/` is excluded — it holds build output including ~80G of QEMU test-run disk
images. `install/` and `installer/` are excluded as Arch-specific `pacman` and
partitioning scripts.

Pinned to the last **pushed** MagikOS commit. Your local checkout had 3 commits
ahead of `origin/main` (and an uncommitted `config/sway/bindings.conf`), so push
those and bump `rev` in `nix/magikos.nix` to pick them up.

## Port status

Working:

- `magikos` package builds: 115M, 417 wrappers, no broken symlinks
- All 47 runtime dependencies resolve against nixpkgs
- Sway session, PipeWire, SDDM, `programs.sway.xwayland`
- 8 MagikOS systemd *user* units ported to `systemd.user.services`
- Sudo rules from `etc/sudoers.d` (note `%wheel` is a group, not a user list)
- Dotfiles deployed: `sway`, `alacritty`, `foot`, `kitty`, `ghostty`, `fish`,
  `fuzzel`, `wofi`, and the rest of `config/`

Not yet ported:

- **`bin/magikos-pkg-backend` requires `pacman` or `apt-get`.** There is no Nix
  backend, so every `magikos pkg` subcommand fails, and ~60 scripts call
  `magikos-pkg-add` to self-heal missing dependencies. This is the main blocker
  and it wants an upstream change in the MagikOS repo, not a packaging hack.
- **`~/.config/magikos` is deliberately not managed.** It is per-user state —
  installed plugins, chosen theme, `shell.json`, and ~150M of wallpapers.
  Symlinking the packaged baseline over it would destroy all of it. Use the
  `dotfiles/` escape hatch if you want to version it.
- Boot chain (Limine/mkinitcpio/snapper/UKI), Plymouth, SDDM theme, snapper,
  `app.slice` OOM settings, and the Arch-only `etc/` drop-ins have no Nix
  equivalents yet.

## Hosts

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
- **Login/password:** `users.users.magikxiii` in `configuration.nix` sets no password. On an existing install the
  current password is preserved, but on a *fresh* install the account is created locked. Set one with
  `sudo passwd magikxiii` (or add `hashedPassword`/`initialPassword` locally) or you will not be able to log in.
