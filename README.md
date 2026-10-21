# NixOSBuild

NixOS + Home Manager configuration running **MagikOS** (Sway + QuickShell shell),
ported from an existing CachyOS/MagikOS machine.

## What this repo contains

| Path | Purpose |
|---|---|
| `flake.nix` | Two NixOS hosts + a standalone Home Manager config |
| `nix/magikos.nix` | Packages MagikOS from the upstream git repo into the store |
| `nix/module.nix` | NixOS integration: systemd user units, sudo rules, `MAGIKOS_PATH` |
| `nix/parity.nix` | The Arch-only drop-ins under `default/` + `/etc`, ported |
| `patches/` | Changes carried against upstream MagikOS, rather than vendored |
| `hosts/home.nix` | Home Manager dotfiles, sourced from the packaged config tree |
| `hosts/vm.nix` | QEMU test-VM hardware profile |
| `hosts/iso.nix` | Bootable installer CD (minimal NixOS + MagikOS) |
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
   Those wrappers use an absolute `#!` store path for the same reason as (1):
   a `#!/usr/bin/env bash` shebang exits 127 on NixOS, because `/usr/bin/env`
   is not in the closure. The runtime closure is *also* installed into the
   system profile by `nix/module.nix`, because sway's autostart runs
   `exec quickshell ...` directly rather than through a wrapper.

`iso/` is excluded — it holds build output including ~80G of QEMU test-run disk
images. `install/` and `installer/` are excluded as Arch-specific `pacman` and
partitioning scripts.

Pinned to MagikOS `49b1304`, with `patches/nix-pkg-backend.patch` applied on top.
MagikOS `main` is deliberately left alone; the same change is pushed to the
`nix-pkg-backend` branch and open upstream as a PR:

```
https://github.com/ArchMagikXIII/MagikOS/compare/main...nix-pkg-backend
```

Once it lands upstream, drop the `patches` line and bump `rev`/`hash`.

## Port status

Verified by booting the `vm` host under QEMU and inspecting the running guest.

Working:

- `magikos` package builds: 115M, 417 wrappers, no broken symlinks
- All 47 runtime dependencies resolve against nixpkgs
- Both hosts build `system.build.toplevel` cleanly
- Boots to the SDDM `magikos` theme, autologins into Sway, and the MagikOS
  QuickShell bar starts (`quickshell -p $MAGIKOS_PATH/shell`)
- `systemctl --failed` reports nothing, in both the system and user managers
- 8 MagikOS systemd *user* units ported to `systemd.user.services`
- Sudo rules from `etc/sudoers.d` (note `%wheel` is a group, not a user list)
- Dotfiles seeded into `~/.config`: `sway`, `alacritty`, `foot`, `kitty`,
  `ghostty`, `fish`, `fuzzel`, `wofi`, and the rest of `config/`
- Everything in `default/` and `/etc` that had a NixOS equivalent (see below)

Ported via `patches/nix-pkg-backend.patch`: `bin/magikos-pkg-backend` gained a
Nix backend. Nix has no package database, so `pkg_installed` answers from the profile
closure -- snapshotted once into a cache keyed on the profile generation, then
grepped by attribute name. A transaction that genuinely needs a package fails
loudly and points at the flake instead of mutating the store, because installing
into a user profile would be silently undone by the next rebuild. Transactions
no longer escalate, since user profiles are unprivileged. Covered by eight new
cases in `test/shell.d/pkg-backend-test.sh`.

`nix/parity.nix` maps each Arch drop-in to its NixOS option. Nothing here is
copied verbatim -- the file is the index:

| Arch | NixOS |
|---|---|
| `/etc/sysctl.d/90-magikos-file-watchers.conf` | `boot.kernel.sysctl` |
| `/etc/sysctl.d/99-magikos-sysctl.conf` | `boot.kernel.sysctl` |
| `/etc/sysctl.d/99-magikos-desktop-tuning.conf` | `boot.kernel.sysctl` |
| `/etc/modprobe.d/99-amdgpu-overdrive.conf` | `boot.extraModprobeConfig` |
| `/etc/modprobe.d/magikos-usb-autosuspend.conf` | `boot.extraModprobeConfig` |
| `/etc/systemd/oomd.conf.d/10-magikos.conf` | `systemd.oomd.settings.OOM` |
| `user/app.slice.d/10-oomd.conf` | `systemd.user.slices.app.sliceConfig` |
| `/etc/systemd/system.conf.d/*` | `systemd.settings.Manager` |
| `/etc/systemd/user.conf.d/20-magikos-nofile.conf` | `systemd.user.settings.Manager` |
| `/etc/systemd/logind.conf.d/*` | `services.logind.settings.Login` |
| `/etc/udev/*.rules` | `services.udev.packages` |
| `default/systemd/system-sleep/*` | `environment.etc` |
| `/etc/plymouth/plymouthd.conf` | `boot.plymouth` |
| `/etc/sddm.conf.d/10-theme.conf` | `services.displayManager.sddm.theme` |
| `/etc/snapper/configs/root` | `services.snapper.configs.root` |
| `default/limine-entry-tool.d/*.conf` | `boot.kernelParams` |

`~/.config` is **seeded, not symlinked.** The packaged tree is copied in as
real, writable files, once, guarded by `[ ! -e ... ]`.

Symlinking it into the store looks tempting and does not work: the store is
read-only, and applications write inside their own config directories. fish
cannot save universal variables, fcitx5 cannot write its profile, chromium
cannot save `Preferences`, and opencode exits on startup writing
`service-prod.json`. Linking the individual files instead of the directories
only moves the problem, because anything that rewrites a file in place still
gets `EROFS`.

Copying is also what upstream does: MagikOS seeds `/etc/skel/.config` and never
re-copies afterwards, keeping `share/magikos/config` as the resync source. The
practical consequence is that edits to the packaged configs here do **not**
propagate on rebuild -- delete `~/.config/<name>` to take the packaged version
again. `./dotfiles/<name>` remains the versioned escape hatch, and is the one
thing still symlinked, since it is authored in this repo rather than generated.

## Known deviations

Four things are deliberately *not* at parity, all of them needing a NixOS-native
replacement rather than a file port:

1. **Limine bootloader.** The source system boots Limine with a UKI and a
   snapper-integrated entry tool. Here it is systemd-boot. The kernel command
   line from `default/limine-entry-tool.d/` is ported verbatim, including
   `initramfs_async=0`; only the bootloader itself differs.
2. **Wayland SDDM greeter.** The source greeter runs `CompositorCommand=sway`.
   nixpkgs' `sddm.wayland.compositor` only accepts `weston` or `kwin`, so the
   X11 greeter is kept instead -- which also supplies the XWayland that Sway
   needs for X11 apps. Set
   `services.displayManager.sddm.wayland.enable = true` if you want to try it.
3. **`NUMBER_LIMIT_IMPORTANT=5` in snapper.** nixpkgs' snapper module does not
   expose the `NUMBER_*` keys, so this stays at snapper's default of 10.
   `NUMBER_LIMIT` (5) is already snapper's default and matches.
4. **BBR.** `net.ipv4.tcp_congestion_control = bbr` is set, but the module is
   not force-loaded: if a given kernel lacks BBR the kernel keeps cubic and
   logs a warning, which beats failing to boot on a module that may not exist.

Open item, not yet explained: `magikos-sleep-lock`
(`magikos-system-sleep-monitor`) exits 0 immediately in the QEMU guest, so
systemd restarts it every few seconds. The guest has no lid or suspend path, so
this may simply be correct behaviour headless -- it is not reproduced by any
of the above.

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

This flake exposes three hosts. They share `configuration.nix` (desktop, packages,
services) but have completely separate hardware profiles.

| Host | Profile | Disk layout | Bootloader |
|---|---|---|---|
| `cachyos-x8664` | `hardware-configuration.nix` | btrfs subvolumes, separate vfat `/boot` | systemd-boot (UEFI) |
| `vm` | `hosts/vm.nix` | single ext4 `/`, no `/boot` | none — booted via QEMU `-kernel`/`-initrd` |
| `iso` | `hosts/iso.nix` | live CD (squashfs) | ISOLINUX + EFI |

Build them by suffix:

```bash
sudo nixos-rebuild switch --flake .#cachyos-x8664   # real machine
sudo nixos-rebuild switch --flake .#vm              # QEMU test VM
```

The `vm` host is a disposable QEMU guest: it has no EFI system partition, so
*no* bootloader is installed. It autologins into Sway through SDDM, and also
sets `services.getty.autologinUser` so the serial console is usable --
`configuration.nix` intentionally sets no user password, which would otherwise
leave the account locked and the guest undebuggable. Its hostname is
`magikos-vm`, not `cachyos-x8664`.

The simplest way to run it is `system.build.vm`, which needs no disk at all:

```bash
nix run .#nixosConfigurations.vm.config.system.build.vm
```

The `iso` host produces a bootable installer CD:

```bash
nix build .#nixosConfigurations.iso.config.system.build.isoImage
# result/iso/nixos-minimal-*.iso  (also copied to ~/nixos-magikos-installer.iso)
```

Flash it to a USB stick and boot any machine from it. The live CD runs as root
on tty1 with Intel i915 KMS enabled (targeting the HP x360 14 / Pentium N5000),
carries the flake at `/iso/NixOSBuild`, and installs the `cachyos-x8664` host
with `nixos-install --flake /iso/NixOSBuild#cachyos-x8664`. The target disk's
UUIDs must match `hardware-configuration.nix`, or run `nixos-generate-config`
first.

Note that `hosts/vm.nix` sets `virtualisation.vmVariant`, not the outer
`virtualisation` options: this nixpkgs builds `system.build.vm` from a separate
module evaluation that pulls in `qemu-vm.nix`, so `memorySize`, `cores` and
`qemu.options` only exist *inside* `vmVariant`. The defaults are 1024 MiB, one
vCPU and no GPU, which reaches a serial console but not a desktop -- Sway's DRM
backend needs a render node. The repo sets 8 GiB, 4 vCPU and a `virtio-gpu-pci`
so the stock runner is usable as-is. Recreating it by hand instead:

```bash
-kernel /nix/store/*-nixos-system-vm-*/kernel-modules/lib/modules/*/vmlinuz \
-initrd /nix/store/*-nixos-system-vm-*/initrd \
-append "init=/nix/store/*-nixos-system-vm-*/init" \
-device virtio-gpu-pci \
-drive file=vm.qcow2,if=virtio
```

A guest screenshot via the QEMU monitor's `screendump` comes back black: Sway
renders straight to DRM and never touches the virtual console, so the monitor
has nothing to capture. Check the session from inside instead --
`pgrep -c quickshell` and `systemctl --failed` are the useful ones.

### The init on the kernel command line decides which profile you get

The guest has no bootloader, so the `init=` on the kernel command line is
what it boots. It has to name the init of the **same build** the kernel and
initrd came from, or the guest comes up on one profile's kernel and another
profile's `/etc`.

This bites in a way that is easy to misread. The `vm` profile has no
bootloader and no `/boot` partition, so nothing inside the guest can change
what it boots -- the kernel command line comes from whatever launched the
VM. Launch it with a stale init and the guest lands on the old profile:

```
$ readlink /run/current-system
/nix/store/...-nixos-system-cachyos-x8664-...
```

and everything that the current profile owns is missing. There is no
`/etc/magikos` symlink, so the bar cannot find its configuration at all:

```
Could not open config file at "/etc/magikos/shell"
```

`nixos-rebuild switch` does not help across a reboot, because the reboot
replaces `/etc` with the booted profile's copy. So the fix is on the side
that launches the VM: use the runner, or point the three paths at one
build.

```bash
# the runner, which keeps the three in step
nix run .#nixosConfigurations.vm.config.system.build.vm

# or by hand, from one build
build=$(nix build .#nixosConfigurations.vm.config.system.build.toplevel --no-link --print-out-paths)
qemu-system-x86_64 \
  -kernel "$build"/kernel-modules/lib/modules/*/vmlinuz \
  -initrd "$build"/initrd \
  -append "init=$build/init" \
  -device virtio-gpu-pci \
  -drive file=vm.qcow2,if=virtio
```

Check which profile a guest is on with `readlink /run/current-system`. If it
is not the one it should be, `magikos-vm-sync` re-applies the intended
profile and restarts the shell; it lives in `~/.local/bin` rather than the
system profile precisely so that it is still there on a guest that booted the
wrong one.

```bash
magikos-vm-sync
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
