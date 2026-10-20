{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ ];

  # Host
  networking.hostName = "cachyos-x8664";

  # Boot vfat EFI partition
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/8DF5-4E58";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };

  # Btrfs root (@)
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/65a92e99-58c7-47e9-8d71-7b6c53c79697";
    fsType = "btrfs";
    options = [ "subvol=/@" "compress=zstd:1" "noatime" ];
  };

  # Btrfs home (@home)
  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/65a92e99-58c7-47e9-8d71-7b6c53c79697";
    fsType = "btrfs";
    options = [ "subvol=/@home" "compress=zstd:1" "noatime" ];
  };

  # Additional btrfs subvolumes from the source system
  fileSystems."/root" = {
    device = "/dev/disk/by-uuid/65a92e99-58c7-47e9-8d71-7b6c53c79697";
    fsType = "btrfs";
    options = [ "subvol=/@root" "compress=zstd:1" "noatime" ];
  };

  fileSystems."/srv" = {
    device = "/dev/disk/by-uuid/65a92e99-58c7-47e9-8d71-7b6c53c79697";
    fsType = "btrfs";
    options = [ "subvol=/@srv" "compress=zstd:1" "noatime" ];
  };

  fileSystems."/var/cache" = {
    device = "/dev/disk/by-uuid/65a92e99-58c7-47e9-8d71-7b6c53c79697";
    fsType = "btrfs";
    options = [ "subvol=/@cache" "compress=zstd:1" "noatime" ];
  };

  fileSystems."/var/tmp" = {
    device = "/dev/disk/by-uuid/65a92e99-58c7-47e9-8d71-7b6c53c79697";
    fsType = "btrfs";
    options = [ "subvol=/@tmp" "compress=zstd:1" "noatime" ];
  };

  fileSystems."/var/log" = {
    device = "/dev/disk/by-uuid/65a92e99-58c7-47e9-8d71-7b6c53c79697";
    fsType = "btrfs";
    options = [ "subvol=/@log" "compress=zstd:1" "noatime" ];
  };

  fileSystems."/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "defaults" "mode=1777" ];
  };

  fileSystems."/mnt/SteamGames" = {
    device = "/dev/disk/by-uuid/52f514ed-7116-4169-be74-58f4ba36f622";
    fsType = "ext4";
    options = [ "nofail" ];
  };

  fileSystems."/mnt/ventoy" = {
    device = "/dev/disk/by-uuid/4E21-0000";
    fsType = "exfat";
    options = [ "defaults" "nofail" "x-systemd.automount" "users" "uid=1000" "gid=1000" ];
  };

  # ZRAM swap (source system used zram ~39G)
  zramSwap.enable = true;

  # Allow btrfs + exfat
  boot.supportedFilesystems = [ "btrfs" "exfat" ];

  # Snapshot the root subvolume for pre-update recovery. Only meaningful here:
  # the root below is btrfs, whereas the QEMU guest's root is ext4.
  magikos.snapper.enable = true;
}
