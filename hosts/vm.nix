{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ../configuration.nix
  ];

  # This VM has a single ext4 partition and no EFI system partition. Its
  # /etc/nixos/hardware-configuration.nix configures no bootloader at all, which
  # means it is booted straight from the kernel/initrd via QEMU's -kernel /
  # -initrd flags. Installing any bootloader here would fail because there is no
  # /boot to install into, so keep every loader off.
  boot.loader = {
    systemd-boot.enable = lib.mkForce false;
    grub.enable = lib.mkForce false;
    efi.canTouchEfiVariables = lib.mkForce false;
  };

  # Single ext4 root, no subvolumes, no separate /boot or /home.
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/963ab8ea-dbca-463a-acf9-4270bd7587d7";
    fsType = "ext4";
  };

  swapDevices = [ ];

  # Virtio devices, as detected by the installer.
  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "virtio_pci"
    "sr_mod"
    "virtio_blk"
  ];
  boot.kernelModules = [ "kvm-amd" ];

  # There is no real firmware behind a vCPU, so microcode updates are pointless.
  hardware.cpu.amd.updateMicrocode = lib.mkForce false;

  # The real machine gets its swap from hardware-configuration.nix; the VM needs
  # its own since it does not import that file.
  zramSwap.enable = true;

  # `configuration.nix` enables SDDM but never sets a password for the user, so
  # log in through the greeter would be impossible. Autologin straight into Sway.
  services.displayManager.defaultSession = "sway";
  services.displayManager.autoLogin = {
    enable = true;
    user = "magikxiii";
  };
  # Log straight back in when a session ends. Without it SDDM drops to the
  # greeter and waits, which is the wrong behaviour for a disposable guest
  # that is meant to come back on its own after a config change or a
  # restart of the compositor.
  services.displayManager.sddm.autoLogin.relogin = true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Not "cachyos-x8664": the shared configuration.nix no longer hardcodes a
  # name, so each hardware profile owns its own.
  networking.hostName = "magikos-vm";

  # Console access for debugging. `configuration.nix` deliberately sets no
  # password for the user, which leaves the account locked, so without this
  # there is no way into a serial console to diagnose a failed boot. agetty's
  # --autologin bypasses the password check, so this needs no password, and it
  # only ever runs on this throwaway guest.
  services.getty.autologinUser = "magikxiii";

  # `system.build.vm` is built from `virtualisation.vmVariant`, which is a
  # separate module evaluation that pulls in qemu-vm.nix -- so the QEMU knobs
  # (memorySize, cores, qemu.options) only exist *inside* vmVariant, not in this
  # configuration. Set them here or they stay at qemu-vm.nix's defaults.
  #
  # The defaults are 1024 MiB, 1 vCPU and no GPU at all, which is enough to
  # reach a serial console but not a desktop: Sway's DRM backend needs a render
  # node, so with no GPU device the session never comes up and the guest looks
  # dead. virtio-gpu is what provides that node under QEMU.
  virtualisation.vmVariant = {
    virtualisation.memorySize = 8192;
    virtualisation.cores = 4;
    virtualisation.qemu.options = [ "-device" "virtio-gpu-pci" ];
  };
}
