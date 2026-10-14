{ config, lib, pkgs, ... }:

let
  cfg = config.magikos;
  magikos = cfg.package;
  magikosPath = "${magikos}/share/magikos";
  bin = name: "${magikos}/bin/${name}";
in
{
  options.magikos = {
    enable = lib.mkEnableOption "the MagikOS desktop environment (Sway + QuickShell shell)";

    package = lib.mkPackageOption pkgs "magikos" { };

    userUnits = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the MagikOS systemd *user* units that default/systemd/user ships.";
    };

    sudoRules = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Grant the passwordless sudo rules from etc/sudoers.d. These are
        deliberately narrow, except for `magikos-dns`, which is granted only
        for its three named providers -- the upstream file omits `Custom` on
        purpose because it points the machine at caller-supplied servers.
      '';
    };

    tailscale = {
      enable = lib.mkEnableOption "the MagikOS Tailscale Taildrop receiver";
      package = lib.mkPackageOption pkgs "tailscale" { };
    };
  };

  config = lib.mkIf cfg.enable {
    # All ~417 magikos-* commands land on PATH via the package wrappers, which
    # also export MAGIKOS_PATH and the runtime dependency closure.
    environment.systemPackages = [
      magikos
      pkgs.fcitx5
    ] ++ lib.optional cfg.tailscale.enable cfg.tailscale.package;

    # The 65 scripts that read MAGIKOS_PATH default it to /usr/share/magikos.
    # Sessions that never touch the wrappers (systemd units, quickshell's own
    # Process calls, sway exec lines) rely on this instead.
    environment.sessionVariables.MAGIKOS_PATH = magikosPath;

    # wayland-wm-app-daemon.service ships with uwsm, and MagikOS's sleep-lock
    # and autostart units expect it to exist.
    programs.uwsm.enable = true;

    security.polkit.enable = true;

    # --- Privileged bits from etc/sudoers.d ---------------------------------
    security.sudo.extraConfig = lib.mkIf cfg.sudoRules ''
      Defaults passwd_tries=10
    '';

    security.sudo.extraRules = lib.mkIf cfg.sudoRules [
      # etc/sudoers.d/magikos-dns. Note %wheel is a *group*, not a user list.
      {
        groups = [ "wheel" ];
        runAs = "root";
        commands = map (provider: {
          command = "${bin "magikos-dns"} ${provider}";
          options = [ "NOPASSWD" ];
        }) [ "Cloudflare" "Google" "DHCP" ];
      }
      # etc/sudoers.d/magikos-tzupdate
      {
        groups = [ "wheel" ];
        runAs = "root";
        commands = [
          {
            command = "${pkgs.systemd}/bin/timedatectl set-timezone *";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    # --- systemd user units -------------------------------------------------
    #
    # These are ported from default/systemd/user/*.service rather than copied
    # verbatim: the Arch files hardcode /usr/bin/magikos-*, which does not
    # exist in a Nix closure, so each ExecStart points into the store instead.
    systemd.user.services = lib.mkIf cfg.userUnits {

      bt-agent = {
        description = "Bluetooth pairing agent (auto-accept)";
        after = [ "dbus.socket" ];
        requires = [ "dbus.socket" ];
        unitConfig.ConditionPathIsDirectory = "/sys/class/bluetooth";
        # Skip cleanly on machines with no usable adapter rather than
        # restart-looping.
        serviceConfig = {
          Type = "simple";
          ExecCondition = "${pkgs.systemd}/bin/systemctl is-active --quiet bluetooth.service";
          ExecStart = "${pkgs.bluez}/bin/bt-agent -c NoInputNoOutput";
          Restart = "on-failure";
          RestartSec = 2;
        };
        wantedBy = [ "graphical-session.target" ];
      };

      magikos-crash-watch = {
        description = "Announce process crashes and offer an AI diagnosis";
        after = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
        unitConfig.ConditionPathExists = "!%h/.local/state/magikos/toggles/crash-capture-off";
        serviceConfig = {
          Type = "simple";
          ExecStart = bin "magikos-crash-watch";
          Restart = "always";
          RestartSec = 5;
        };
        wantedBy = [ "graphical-session.target" ];
      };

      magikos-fcitx5 = {
        description = "Fcitx5 input method (XCompose sequences)";
        after = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.fcitx5}/bin/fcitx5 --disable notificationitem";
          # always, not on-failure: fcitx5 exits 0 when another instance owns
          # its bus name, and a clean exit still leaves the user with no IM.
          Restart = "always";
          RestartSec = 2;
        };
        wantedBy = [ "graphical-session.target" ];
      };

      magikos-migrate-notify = {
        description = "Notify about pending MagikOS migrations";
        after = [ "graphical-session.target" ];
        unitConfig.ConditionPathIsDirectory = "${magikosPath}/migrations";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = bin "magikos-migrate-notify";
        };
        wantedBy = [ "graphical-session.target" ];
      };

      magikos-recover-internal-monitor = {
        description = "Recover the internal monitor toggle when no external display is connected";
        before = [ "graphical-session-pre.target" ];
        unitConfig.ConditionPathExists = "%h/.local/state/magikos/toggles/internal-monitor-disable";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = bin "magikos-hw-recover-internal-monitor";
        };
        wantedBy = [ "graphical-session-pre.target" ];
      };

      magikos-sleep-lock = {
        description = "Lock MagikOS before suspend";
        after = [ "dbus.socket" "wayland-session-waitenv.service" ];
        requires = [ "dbus.socket" ];
        partOf = [ "graphical-session.target" ];
        unitConfig.ConditionEnvironment = [ "MAGIKOS_PATH" "WAYLAND_DISPLAY" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = bin "magikos-system-sleep-monitor";
          Restart = "always";
          RestartSec = 2;
        };
        wantedBy = [ "graphical-session.target" ];
      };

      magikos-speaker-tuning = {
        description = "MagikOS speaker tuning filter-chain";
        after = [ "pipewire.service" "wireplumber.service" ];
        requires = [ "pipewire.service" ];
        wants = [ "wireplumber.service" ];
        partOf = [ "pipewire.service" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.pipewire}/bin/pipewire -c magikos-speaker-tuning.conf";
          Restart = "on-failure";
          RestartSec = 2;
        };
        wantedBy = [ "graphical-session.target" ];
      };

      magikos-tailscale-receive = lib.mkIf cfg.tailscale.enable {
        description = "Save incoming Taildrop files to the downloads directory";
        serviceConfig = {
          Type = "simple";
          ExecStart = bin "magikos-tailscale-receive";
          Restart = "always";
          RestartSec = 5;
        };
        wantedBy = [ "graphical-session.target" ];
      };
    };
  };
}