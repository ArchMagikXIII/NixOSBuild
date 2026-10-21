{
  lib,
  stdenvNoCC,
  fetchgit,
  bash,
  coreutils,
  gnused,
  gnugrep,
  findutils,
  gawk,
  python3,
  jq,
  gum,
  sway,
  swaybg,
  swaylock,
  wl-clipboard,
  wtype,
  wlsunset,
  quickshell,
  uwsm,
  foot,
  kitty,
  ghostty,
  alacritty,
  brightnessctl,
  playerctl,
  grim,
  slurp,
  ffmpeg,
  imagemagick,
  inotify-tools,
  procps,
  util-linux,
  xdg-utils,
  xdg-user-dirs,
  fontconfig,
  gnupg,
  libxkbcommon,
  curl,
  git,
  libnotify,
  gvfs,
  nautilus,
  fprintd,
  xwayland,
  mesa-demos,
  pciutils,
  desktop-file-utils,
  vulkan-tools,
  fzf,
  ripgrep,
  tmux,
  dbus,
  systemd,

  # Runtime deps that MagikOS expects on PATH. Deliberately excludes anything
  # that does not exist on NixOS (pacman, yay, mkinitcpio, limine, snapper).
  runtimeDeps ? [
    bash
    coreutils
    gnused
    gnugrep
    findutils
    gawk
    python3
    jq
    gum
    sway
    swaybg
    swaylock
    wl-clipboard
    wtype
    wlsunset
    quickshell
    uwsm
    foot
    kitty
    ghostty
    alacritty
    brightnessctl
    playerctl
    grim
    slurp
    ffmpeg
    imagemagick
    inotify-tools
    procps
    util-linux
    xdg-utils
    xdg-user-dirs
    fontconfig
    gnupg
    libxkbcommon
    nautilus
    curl
    git
    libnotify
    # dbus-monitor is how magikos-system-sleep-monitor waits for logind's
    # PrepareForSleep signal. A systemd unit's PATH is the user manager's
    # DefaultEnvironment, which is not guaranteed to carry the system
    # profile -- and when it does not, the coproc's exec fails, the pipe
    # hits EOF, the monitor exits 0 and systemd restarts the unit forever.
    dbus
    systemd
    gvfs
    fprintd
    xwayland
    mesa-demos
    pciutils
    desktop-file-utils
    vulkan-tools
    fzf
    ripgrep
    tmux
  ],
}:

stdenvNoCC.mkDerivation {
  pname = "magikos";
  version = "1.0.0.beta";

  src = fetchgit {
    url = "https://github.com/ArchMagikXIII/MagikOS.git";
    rev = "d5f89923f4aefa7e542f3ea10ec8375807a6fe5f";
    hash = "sha256-V6ZKkh63jRXJWBjYVWbEaWL+0tc96IsIMTLxfBPQGFM=";
  };

  # magikos-upstream-fixes.patch carries the fixes that are committed in the
  # MagikOS checkout but not yet in the revision this package pins: the
  # missing metadata summaries on the two OpenRC commands, the command
  # helpers replacing raw `command -v`, quickshell's --no-duplicate flag on
  # the sway autostart, and the package backend suite learning about the nix
  # backend. Without them the package ships a tree whose own
  # `magikos commands --check` fails, and a sway reload starts a second bar.
  #
  # It is carried here so the port builds the same thing from a pinned
  # upstream source, rather than depending on a revision that does not
  # exist yet. Drop it and bump rev/hash once the fixes are upstream.
  #
  # The nix package backend itself is not carried here any more: upstream
  # merged it (8a38973a, "Add a Nix package backend so MagikOS runs on
  # NixOS"), so the pinned revision already has it.
  patches = [ ../patches/magikos-upstream-fixes.patch ];

  dontBuild = true;

  strictDeps = true;

  installPhase = ''
    runHook preInstall

    magikosDir="$out/share/magikos"
    mkdir -p "$magikosDir" "$out/bin"

    # Ship the runtime payload. `iso/` is deliberately excluded: it holds build
    # output (release ISOs and ~80G of test-run disk images), and `install/` plus
    # `installer/` are Arch pacman/partitioning scripts that cannot apply here.
    for dir in bin shell themes wallpapers config default applications \
                manual docs agents plans migrations \
                icon.png icon.txt logo.svg logo.txt version; do
      if [ -e "./$dir" ]; then
        cp -r "./$dir" "$magikosDir/"
      fi
    done

    # `cp -r` carries the store's read-only permissions across, and sed needs to
    # create temp files next to each file it rewrites.
    chmod -R u+w "$magikosDir"

    # --- Rewrite absolute paths that do not exist on NixOS ------------------
    #
    # 1. Shebangs. 404 scripts use #!/bin/bash and 2 use #!/usr/bin/python3;
    #    neither path exists in the Nix store closure.
    #
    #    This has to cover the whole tree, not just bin/: the shell's plugin
    #    helpers (shell/plugins/*/ *.sh, shell/services/*.sh), the udev rule
    #    helper (default/udev/g435-volume.sh) and the systemd suspend hooks
    #    (default/systemd/system-sleep/*) all carry a #!/bin/bash shebang too.
    #    Left alone they die with "bad interpreter" the moment something
    #    invokes them -- the clipboard plugin and the image picker silently
    #    stop working, the G435 volume rule never fires, and every suspend
    #    fails its hooks.
    #
    #    The patterns are anchored on "#!" so that a file whose *first* line
    #    merely mentions "sh" (a Markdown heading, say) is left alone, and only
    #    line 1 is ever rewritten, so a shebang quoted inside a doc file is
    #    untouched.
    find "$magikosDir" -type f -print0 | while IFS= read -r -d $'\0' f; do
      if head -c 2 "$f" | grep -q '#!'; then
        case "$(head -n1 "$f")" in
          '#!'*python3*) sed -i "1s|.*|#!${python3}/bin/python3|" "$f" ;;
          '#!'*bash*)    sed -i "1s|.*|#!${bash}/bin/bash|"      "$f" ;;
          '#!'*sh)       sed -i "1s|.*|#!${bash}/bin/bash|"      "$f" ;;
        esac
      fi
    done

    # 2. The packaged tree lives in the store, not /usr/share/magikos. 112
    #    files across the repo reference the old prefix; rewrite it so
    #    references that bypass MAGIKOS_PATH still resolve. `grep -I` limits
    #    this to text files, so wallpapers and icons are left untouched.
    #
    #    The replacement is /etc/magikos, a stable symlink into the current
    #    package that module.nix maintains, rather than the store path
    #    itself. A store path changes with every rebuild of the package, and
    #    these references end up copied into ~/.config, where they would
    #    silently point at a stale -- or garbage-collected -- build. A stable
    #    path means the seeded config keeps working across rebuilds.
    grep -rIl "/usr/share/magikos" "$magikosDir" 2>/dev/null \
      | xargs -r sed -i "s|/usr/share/magikos|/etc/magikos|g"

    # 3. /usr/bin/<tool> does not exist on NixOS; binaries live on PATH. The
    #    in-tree uwsm-app and xdg-terminal-exec wrappers and the quickshell
    #    autostart both hardcode it.
    grep -rIl -e "/usr/bin/quickshell" -e "/usr/bin/uwsm-app" \
               -e "/usr/bin/xdg-terminal-exec" "$magikosDir" 2>/dev/null \
      | xargs -r sed -i \
        -e 's|/usr/bin/quickshell|quickshell|g' \
        -e 's|/usr/bin/uwsm-app|uwsm-app|g' \
        -e 's|/usr/bin/xdg-terminal-exec|xdg-terminal-exec|g'

    # 4. The sway config resolves MAGIKOS_PATH from the environment, falling
    #    back to the packaged root. On the Arch system that fallback is
    #    /usr/share/magikos and the environment is not set, so the fallback is
    #    what is used. Here the environment *is* set, by /etc/set-environment,
    #    and it wins -- so the value that reaches the bar is whatever the
    #    session happened to start with. A session that began before the
    #    environment was corrected keeps the old store path, and the bar then
    #    reads its plugins from a build that is no longer current.
    #
    #    The sway config is the one place that should not depend on the
    #    session environment at all: it is the compositor's own config, and the
    #    compositor is what the environment describes. Naming the root
    #    directly makes the config self-contained, so a stale environment
    #    cannot reintroduce the split.
    #
    #    Only the sway config is rewritten. The bin scripts keep the
    #    environment-first form, because the package wrappers set
    #    MAGIKOS_PATH to the precise store path and that is what they should
    #    use.
    grep -rIl 'export MAGIKOS_PATH="''${MAGIKOS_PATH:-/etc/magikos}"' "$magikosDir/config/sway" 2>/dev/null \
      | xargs -r sed -i \
        's|export MAGIKOS_PATH="''${MAGIKOS_PATH:-/etc/magikos}"|export MAGIKOS_PATH=/etc/magikos|g'

    # 5. The sway autostart starts the bar with quickshell's --no-duplicate
    #    flag. The flag means "exit immediately if another instance of the
    #    given config is already running", and without it a sway reload --
    #    which re-runs the autostart line -- starts a second bar next to the
    #    one the shell's own supervisor is holding. The supervisor already
    #    uses the flag, so with it on both sides a reload leaves the desktop
    #    as it found it.
    sed -i 's|exec quickshell -p |exec quickshell -n -p |g' "$magikosDir/config/sway/autostart.conf"

    # 6. magikos-dns re-invokes itself as root, through the path the sudo
    #    rule grants. It hardcodes /usr/bin/magikos-dns, which is the Arch
    #    install path; here the rule names the wrapper in this package's
    #    output, so the hardcoded path has to become that or the re-exec
    #    cannot find the command and the sudo check never matches.
    grep -rIl "/usr/bin/magikos-dns" "$magikosDir" 2>/dev/null \
      | xargs -r sed -i "s|/usr/bin/magikos-dns|$out/bin/magikos-dns|g"

    # --- Expose every script as a wrapped command --------------------------
    #
    # MAGIKOS_PATH must be set for the ~65 scripts that read it, and the runtime
    # deps must be on PATH even when invoked outside a login shell (systemd
    # units, quickshell, sway exec lines).
    depPath=${lib.makeBinPath runtimeDeps}
    for f in "$magikosDir"/bin/*; do
      [ -f "$f" ] || continue
      # Only executable scripts get a wrapper. A few files in bin/ are meant
      # to be sourced rather than run -- magikos-pkg-backend is the one the
      # package commands source, and it carries no executable bit. Wrapping
      # it produced two failures at once: the wrapper's exec died with
      # "Permission denied" when something invoked it directly, and the
      # wrapper shadowed the sourceable script on PATH, so
      # `source magikos-pkg-backend` ran the wrapper instead of the file.
      #
      # A sourceable script is copied verbatim instead, so that
      # `source magikos-pkg-backend` finds the file itself.
      name=$(basename "$f")
      if [ ! -x "$f" ]; then
        cp "$f" "$out/bin/$name"
        continue
      fi
      # An absolute store path, not `#!/usr/bin/env bash`: /usr/bin/env does not
      # exist on NixOS, so an env-based shebang makes every one of these exit
      # 127. The inner script's own shebang was rewritten to the same path
      # above, so `exec "$f"` resolves too. The inner script is executable by
      # construction -- the non-executable ones were copied verbatim above.
      cat > "$out/bin/$name" <<EOF
    #!${bash}/bin/bash
    # /etc/magikos is the stable symlink to this package that the NixOS
    # configuration maintains. It is preferred over the store path so that
    # everything names the same root: the wrappers, the sway config and the
    # shell. That matters for quickshell, which refuses to start a second
    # instance for a path that is already in use -- with two different roots
    # the sway autostart and the shell's own supervisor each start one, and
    # the desktop ends up with two bars.
    #
    # The store path is the fallback so the package still works on its own,
    # outside the configuration that provides the symlink.
    if [ -d /etc/magikos ]; then
      export MAGIKOS_PATH="/etc/magikos"
    else
      export MAGIKOS_PATH="$magikosDir"
    fi
    export PATH="$depPath:\$PATH"
    exec "$f" "\$@"
    EOF
      chmod +x "$out/bin/$name"
    done

    # (permissions were already relaxed above)
    runHook postInstall
  '';

  meta = {
    description = "MagikOS desktop environment (Sway + QuickShell shell), packaged for Nix";
    homepage = "https://github.com/ArchMagikXIII/MagikOS";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };

  # The wrapper scripts put runtimeDeps on PATH for their own children, but
  # nothing inherits that: sway's `exec_always` lines and the QuickShell
  # `Process` calls name tools directly (`exec quickshell ...`), which fails
  # with "quickshell: not found" unless the tools are in the system profile.
  # Exposed so nix/module.nix can install them.
  passthru = {
    inherit runtimeDeps;
  };
}
