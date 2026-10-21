{ config, lib, pkgs, ... }:

let
  cfg = config.magikos;
  magikos = cfg.package;
  magikosPath = "${magikos}/share/magikos";
  bin = name: "${magikos}/bin/${name}";

  # Recovers WAYLAND_DISPLAY and SWAYSOCK from the running compositor and
  # imports them into the systemd user manager. See magikos-session-env below
  # for why that is needed.
  sessionEnvScript = pkgs.writeShellApplication {
    name = "magikos-session-env";
    text = ''
      display=""
      socksock=""
      for _ in $(seq 1 120); do
        for env in /proc/[0-9]*/environ; do
          if [ -r "$env" ]; then
            match=$(tr '\0' '\n' <"$env" 2>/dev/null | grep -m1 '^WAYLAND_DISPLAY=' || true)
            if [ -n "$match" ]; then
              display=''${match#WAYLAND_DISPLAY=}
              sockmatch=$(tr '\0' '\n' <"$env" 2>/dev/null | grep -m1 '^SWAYSOCK=' || true)
              socksock=''${sockmatch#SWAYSOCK=}
              break
            fi
          fi
        done
        if [ -n "$display" ]; then
          break
        fi
        sleep 0.5
      done

      if [ -n "$display" ]; then
        WAYLAND_DISPLAY="$display" systemctl --user import-environment WAYLAND_DISPLAY
      fi
      # SWAYSOCK is what swaymsg needs to reach the compositor, so any user
      # service that shells out to swaymsg needs it in the user manager.
      if [ -n "$socksock" ]; then
        SWAYSOCK="$socksock" systemctl --user import-environment SWAYSOCK
      fi

      # Reach graphical-session.target.
      #
      # SDDM starts the session through its own wayland-session script rather
      # than uwsm, so logind never marks the session graphical and
      # graphical-session.target is never activated. Everything that needs it
      # then stays dead for the whole session: xdg-desktop-portal refuses to
      # start (no file picker, no screen share, no secret portal), and every
      # MagikOS unit that is partOf graphical-session.target never runs.
      #
      # sway-session.target bindsTo graphical-session.target, and bindsTo
      # implies a Requires, so starting it pulls the graphical target in as a
      # dependency. graphical-session.target refuses a manual start on its own
      # ("may be requested by dependency only"), so it has to be reached this
      # way. This mirrors what nixpkgs' own sway session does through
      # /etc/sway/config.d/nixos.conf, which the MagikOS config replaces.
      systemctl --user start sway-session.target || true

      # Best effort: any of these may legitimately refuse to start (no bluetooth
      # adapter, another instance owns the bus name), and none of them should
      # hold up the rest of the session.
      systemctl --user start magikos-crash-watch magikos-fcitx5 magikos-sleep-lock || true
    '';
  };
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
    #
    # The runtime deps are installed system-wide as well, not just referenced by
    # the wrappers. sway's autostart runs `exec quickshell -p $MAGIKOS_PATH/shell`
    # directly rather than through a wrapper, so without these on the system
    # PATH the bar never comes up and the only symptom is
    # "exec: quickshell: not found" in ~/.local/state/magikos/quickshell.log.
    environment.systemPackages = [
      magikos
      pkgs.fcitx5
    ]
    ++ magikos.runtimeDeps
    ++ lib.optional cfg.tailscale.enable cfg.tailscale.package;

    # A stable path to the current MagikOS tree.
    #
    # /etc/magikos is a symlink into the store, repointed on every rebuild.
    # The package rewrites its own /usr/share/magikos references to this path
    # rather than to the store path, because those references get copied into
    # ~/.config, and a store path there would go stale (or get garbage
    # collected) as soon as the package was rebuilt. A stable path keeps the
    # seeded config working across rebuilds.
    environment.etc =
      {
        "magikos".source = "${magikos}/share/magikos";
      }
      // lib.mapAttrs' (
        name: _entry:
        lib.nameValuePair "environment.d/${name}" {
          source = "${magikosPath}/default/environment.d/${name}";
        }
      ) (builtins.readDir "${magikosPath}/default/environment.d");

    # The 65 scripts that read MAGIKOS_PATH default it to /usr/share/magikos.
    # Sessions that never touch the wrappers (systemd units, quickshell's own
    # Process calls, sway exec lines) rely on this instead.
    #
    # Point it at the stable /etc/magikos rather than the store path: this
    # lands in /etc/set-environment, which SDDM hands to the session, so a
    # store path here would leave the whole session -- and the quickshell
    # shell, which reads MAGIKOS_PATH to find its own plugins -- pointing at
    # whichever build happened to be current when the session started.
    environment.sessionVariables.MAGIKOS_PATH = "/etc/magikos";

    # default/environment.d/*.conf are the session-wide environment
    # MagikOS ships: the fcitx5 input-method variables that let Qt, GTK and
    # SDL applications talk to the IME, and SWAY_UNSUPPORTED_GPU, which
    # silences sway's startup advisory about an offloaded NVIDIA card.
    #
    # Nothing installed these, so fcitx5 ran but no application could reach
    # it. They are installed the same way the systemd manager reads them on
    # Arch: as environment.d drop-ins under /etc.

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
    #
    # The ones that already gate on WAYLAND_DISPLAY/MAGIKOS_PATH are wanted by
    # default.target as well as graphical-session.target, because SDDM starts
    # sessions through its own wayland-session script rather than uwsm and so
    # never activates graphical-session.target -- see magikos-session-env
    # below. The rest -- speaker-tuning and the bluetooth agent -- deliberately
    # stay on graphical-session.target alone: speaker-tuning is partOf
    # pipewire.service and would race the session's own pipewire if it started
    # outside one.
    systemd.user.services = lib.mkIf cfg.userUnits {

      # SDDM starts sessions through its own wayland-session script rather than
      # uwsm, and logind has already built the session environment by the time
      # the compositor sets WAYLAND_DISPLAY. So the user manager never sees it,
      # and every unit below that gates on ConditionEnvironment=WAYLAND_DISPLAY
      # is skipped for the whole session and stays inactive -- no bar gap, no
      # crash notifications, no lock-on-suspend, and no input method.
      #
      # Recover the variable from the running compositor's own environment and
      # import it, then start those units by hand. The compositor is up long
      # before this loop gives up, so in practice it resolves on the first
      # few passes; the timeout only bounds the pathological case.
      magikos-session-env = {
        description = "Import WAYLAND_DISPLAY from the compositor into the user manager";
        wantedBy = [ "default.target" ];
        after = [ "dbus.socket" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${sessionEnvScript}/bin/magikos-session-env";
        };
      };

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
        wantedBy = [ "graphical-session.target" "default.target" ];
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
        wantedBy = [ "graphical-session.target" "default.target" ];
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
        wantedBy = [ "graphical-session.target" "default.target" ];
      };

      magikos-speaker-tuning = {
        description = "MagikOS speaker tuning filter-chain";
        after = [ "pipewire.service" "wireplumber.service" ];
        requires = [ "pipewire.service" ];
        wants = [ "wireplumber.service" ];
        partOf = [ "pipewire.service" ];
        # The tuning graph is written by `magikos audio tuning on`, which
        # installs ~/.config/pipewire/magikos-speaker-tuning.conf from the
        # packaged host config. Upstream's first-run script does that on a
        # fresh install, but that script is part of the Arch-only install
        # tree and never runs here -- so on a machine with no tuning applied
        # the unit had nothing to load and sat in a restart loop, failing
        # with exit 254 every two seconds.
        unitConfig.ConditionPathExists = "%h/.config/pipewire/magikos-speaker-tuning.conf";
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
