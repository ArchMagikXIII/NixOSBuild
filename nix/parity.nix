{ config, lib, pkgs, ... }:

# NixOS equivalents of the Arch-only drop-ins MagikOS ships in
# `share/magikos/default/`, plus the hand-written files under /etc that the
# source system installs directly:
#
#   /etc/sysctl.d/90-magikos-file-watchers.conf   -> boot.kernel.sysctl
#   /etc/sysctl.d/99-magikos-*.conf               -> boot.kernel.sysctl
#   /etc/modprobe.d/{99-amdgpu-overdrive,magikos-usb-autosuspend}.conf
#                                                  -> boot.extraModprobeConfig
#   /etc/systemd/oomd.conf.d/10-magikos.conf      -> systemd.oomd.settings.OOM
#   /usr/lib/systemd/user/app.slice.d/10-oomd.conf
#                                                  -> systemd.user.slices.app
#   /etc/systemd/system.conf.d/*                  -> systemd.settings.Manager
#   /etc/systemd/user.conf.d/20-magikos-nofile.conf
#                                                  -> systemd.user.settings.Manager
#   /etc/systemd/logind.conf.d/*                  -> services.logind.settings.Login
#   /etc/plymouth/plymouthd.conf                  -> boot.plymouth
#   /etc/sddm.conf.d/10-theme.conf                -> services.displayManager.sddm.theme
#   /etc/snapper/configs/root                     -> services.snapper.filesystems
#   default/udev/*.rules                          -> services.udev.packages
#   default/systemd/system-sleep/*                -> environment.etc
#   /etc/limine-entry-tool.d/magikos-defaults.conf -> boot.kernelParams
#
# The two things that are deliberately NOT here are documented in README.md
# under "Known deviations": the Limine bootloader and the Wayland SDDM
# greeter. Both need NixOS-native replacements rather than a file port.
let
  cfg = config.magikos;
  magikosPath = "${cfg.package}/share/magikos";

  # MagikOS ships both themes inside the package, laid out for Arch's
  # /usr/share. NixOS looks them up under $out/share/<name>/themes, so each is
  # repackaged into that shape. SDDM's ThemeDir is /run/current-system/sw, so
  # the theme has to be a system package to be found at all; Plymouth takes
  # an explicit package list instead.
  sddmTheme = pkgs.runCommand "magikos-sddm-theme" { } ''
    mkdir -p "$out/share/sddm/themes"
    cp -r "${magikosPath}/default/sddm/magikos" "$out/share/sddm/themes/magikos"
  '';

  plymouthTheme = pkgs.runCommand "magikos-plymouth-theme" { } ''
    mkdir -p "$out/share/plymouth/themes"
    cp -r "${magikosPath}/default/plymouth" "$out/share/plymouth/themes/magikos"
  '';

  # The G435 rule runs a helper script, so it has to name a real path.
  #
  # The package points it at /etc/magikos, the stable symlink the rest of the
  # tree uses, but udev verifies that every program a rule calls exists and is
  # executable when the rules are installed -- and /etc/magikos does not exist
  # yet at that point. The rule is rewritten to the concrete store path here.
  udevRules = pkgs.runCommand "magikos-udev-rules" { } ''
    mkdir -p "$out/lib/udev/rules.d"
    cp "${magikosPath}/default/udev/framework16-qmk-hid.rules" \
       "$out/lib/udev/rules.d/70-framework16-qmk-hid.rules"
    sed "s|/etc/magikos|${magikosPath}|g" \
      "${magikosPath}/default/udev/70-magikos-g435-volume.rules" \
      > "$out/lib/udev/rules.d/70-magikos-g435-volume.rules"
  '';
in
{
  options.magikos.parity = lib.mkEnableOption "the Arch-only drop-ins, ported to NixOS-native equivalents" // {
    default = true;
  };

  options.magikos.snapper = {
    enable = lib.mkEnableOption "btrfs snapshotting for the root subvolume";
    # Off for hosts without a btrfs root (the QEMU guest runs ext4).
    default = false;
  };

  config = lib.mkIf (cfg.enable && cfg.parity) {

    # --- /etc/sysctl.d ----------------------------------------------------
    #
    # The MagikOS tree ships two sysctl files, 90-magikos-file-watchers.conf
    # and 99-magikos-sysctl.conf, and everything below comes from one of them
    # unless it says otherwise.
    boot.kernel.sysctl = {
      # 90-magikos-file-watchers.conf: raise inotify limits so VS Code,
      # webpack and similar dev tools don't hit the 8192 ceiling.
      "fs.inotify.max_user_watches" = 524288;

      # 99-magikos-sysctl.conf
      "net.ipv4.tcp_mtu_probing" = 1;
      "vm.swappiness" = 150;
      "vm.vfs_cache_pressure" = 50;
      "vm.page-cluster" = 0;
      "vm.watermark_boost_factor" = 0;
      "vm.watermark_scale_factor" = 125;
      "vm.dirty_background_bytes" = 67108864;
      "vm.dirty_bytes" = 268435456;
      "vm.dirty_writeback_centisecs" = 1500;

      # Not in the MagikOS tree: no file there sets these. They were carried
      # over from the machine this configuration was ported from, which ran
      # with them, and are kept for the same reason.
      "net.core.rmem_max" = 8388608;
      "net.core.wmem_max" = 8388608;
      # BBR is only usable if the kernel ships it. The sysctl is set
      # unconditionally: if this kernel has no BBR the kernel keeps cubic and
      # logs a warning, which is a better outcome than force-loading a module
      # that may not exist.
      "net.ipv4.tcp_congestion_control" = "bbr";
    };

    # --- /etc/modprobe.d ---------------------------------------------------
    boot.extraModprobeConfig = lib.concatStringsSep "\n" [
      # Not in the MagikOS tree: no file there sets this. Carried over from
      # the machine this configuration was ported from, which ran with it, to
      # disable the undervolt/overclock feature mask so amdgpu takes its
      # default power/clock behaviour.
      "options amdgpu ppfeaturemask=0xFFF7FFFF"
      # magikos-usb-autosuspend.conf: autosuspend fights the external
      # monitors and docks this desktop uses.
      "options usbcore autosuspend=-1"
    ];

    # --- systemd-oomd ------------------------------------------------------
    #
    # Without an OOM daemon the kernel killer only fires once an allocation
    # has already failed, which is far too late for a desktop: the machine
    # thrashes in reclaim until something fails fatally. oomd keys on PSI
    # stall time instead, so it acts while the machine is still thrashing.
    systemd.oomd = {
      enable = true;
      # Only user slices are kill candidates, matching the source system,
      # which never marks the system or root slice.
      enableUserSlices = true;
      enableSystemSlice = false;
      enableRootSlice = false;
      settings.OOM = {
        # 50% means half of a ten-second window was spent stalled on memory
        # reclaim; held for 20s straight the desktop is already unusable.
        DefaultMemoryPressureDurationSec = "20s";
        DefaultMemoryPressureLimit = "50%";
      };
    };

    # Make user apps the only thing oomd is allowed to kill. The compositor
    # runs outside app.slice, so marking only app.slice means the compositor
    # is structurally ineligible and the session survives to show the
    # notification about whatever was killed.
    systemd.user.slices.app.sliceConfig = {
      ManagedOOMMemoryPressure = "kill";
      ManagedOOMSwap = "kill";
    };

    # --- /etc/systemd/system.conf.d and user.conf.d -----------------------
    systemd.settings.Manager = {
      DefaultTimeoutStopSec = "5s";
      DefaultLimitNOFILE = "65536:524288";
    };
    systemd.user.settings.Manager.DefaultLimitNOFILE = "65536:524288";

    # --- /etc/systemd/logind.conf.d ---------------------------------------
    services.logind.settings.Login = {
      # The desktop handles power-button presses itself.
      HandlePowerKey = "ignore";
      # magikos-sleep-lock holds a delay inhibitor so the session is locked
      # before suspend. A delay inhibitor is a timer, not a promise: logind
      # suspends anyway once the window expires, locked or not. Five seconds
      # is not enough when closing the lid also reconfigures displays.
      InhibitDelayMaxSec = 15;
    };

    # --- /etc/udev ---------------------------------------------------------
    services.udev.packages = [ udevRules ];

    # --- /etc/systemd/system-sleep ----------------------------------------
    environment.etc = lib.mapAttrs' (
      name: _entry:
      lib.nameValuePair "systemd/system-sleep/${name}" {
        source = "${magikosPath}/default/systemd/system-sleep/${name}";
        mode = "0755";
      }
    ) (builtins.readDir "${magikosPath}/default/systemd/system-sleep");

    # --- Boot splash -------------------------------------------------------
    boot.plymouth = {
      enable = true;
      theme = "magikos";
      themePackages = [ plymouthTheme ];
    };

    # --- SDDM waits for plymouth ------------------------------------------
    #
    # plymouth-quit.service finishes once plymouthd acknowledges the quit
    # request, but the daemon lingers briefly while releasing DRM master. On
    # fast boots SDDM autologin then launches sway while plymouthd still
    # holds the GPU, and wlroots aborts with "Could not take device: Device or
    # resource busy" -> black screen.
    #
    # Upstream ships this as
    # etc/systemd/system/sddm.service.d/10-wait-for-plymouth.conf. The whole
    # etc/ tree is dropped from the Nix package, so it is ported here as a
    # native ExecStartPre.
    #
    # The leading "-" makes systemd ignore a failure, and pgrep is named by
    # absolute path because a unit's PATH is the bare minimum.
    systemd.services.sddm.serviceConfig.ExecStartPre =
      lib.mkIf config.services.displayManager.sddm.enable [
        "-${pkgs.bash}/bin/bash -c 'for (( i = 0; i < 100; i++ )); do if ! ${pkgs.procps}/bin/pgrep -x plymouthd > /dev/null; then break; fi; sleep 0.1; done'"
      ];

    # --- Login theme -------------------------------------------------------
    #
    # SDDM's ThemeDir is /run/current-system/sw/share/sddm/themes, so this has
    # to be a system package rather than a file in /etc.
    services.displayManager.sddm.theme = "magikos";
    environment.systemPackages = [ sddmTheme ];

    # --- Kernel command line ----------------------------------------------
    #
    # From default/limine-entry-tool.d/magikos-defaults.conf.
    boot.kernelParams = [
      "quiet"
      "splash"
      "loglevel=0"
      "systemd.show_status=false"
      "rd.udev.log_level=0"
      "vt.global_cursor_default=0"
      # Kernel 7.1 unpacks the initramfs asynchronously, which races /init:
      # the early /proc, /sys, /dev and /run mounts fail while unpacking
      # settles, so plymouthd exits when it cannot read /proc/cmdline.
      "initramfs_async=0"
    ];

    # --- Snapper -----------------------------------------------------------
    #
    # default/snapper/root snapshots the root subvolume only, for pre-update
    # recovery. NUMBER_LIMIT (5) is snapper's own default, so only the
    # subvolume and filesystem actually need setting here; NixOS's snapper
    # module does not expose the NUMBER_* keys, so NUMBER_LIMIT_IMPORTANT
    # stays at snapper's default of 10 rather than the source system's 5.
    services.snapper.configs.root =
      lib.mkIf cfg.snapper.enable {
        SUBVOLUME = "/";
        FSTYPE = "btrfs";
      };
  };
}
