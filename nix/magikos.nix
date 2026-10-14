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
    curl
    git
    libnotify
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
    # Pinned to the last pushed commit. The local checkout has 3 newer commits
    # that are not on GitHub yet; bump this once they are pushed.
    rev = "8a38973a52ef99150f369354352373450e43cc6d";
    hash = "sha256-BgrqmrwKIso5SgaCqBIIREJzoYN8ug0DqC0Sa7RW8ZI=";
  };

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
      if [ -e "$src/$dir" ]; then
        cp -r "$src/$dir" "$magikosDir/"
      fi
    done

    # `cp -r` carries the store's read-only permissions across, and sed needs to
    # create temp files next to each file it rewrites.
    chmod -R u+w "$magikosDir"

    # --- Rewrite absolute paths that do not exist on NixOS ------------------
    #
    # 1. Shebangs. 404 scripts use #!/bin/bash and 2 use #!/usr/bin/python3;
    #    neither path exists in the Nix store closure.
    find "$magikosDir/bin" -type f -print0 | while IFS= read -r -d $'\0' f; do
      if head -c 2 "$f" | grep -q '#!'; then
        case "$(head -n1 "$f")" in
          *python*) sed -i "1s|.*|#!${python3}/bin/python3|" "$f" ;;
          *bash*)   sed -i "1s|.*|#!${bash}/bin/bash|"   "$f" ;;
          *sh)      sed -i "1s|.*|#!${bash}/bin/bash|"   "$f" ;;
        esac
      fi
    done

    # 2. The packaged tree lives in the store, not /usr/share/magikos. 112
    #    files across the repo reference the old prefix; rewrite it so
    #    references that bypass MAGIKOS_PATH still resolve. `grep -I` limits
    #    this to text files, so wallpapers and icons are left untouched.
    grep -rIl "/usr/share/magikos" "$magikosDir" 2>/dev/null \
      | xargs -r sed -i "s|/usr/share/magikos|$magikosDir|g"

    # 3. /usr/bin/<tool> does not exist on NixOS; binaries live on PATH. The
    #    in-tree uwsm-app and xdg-terminal-exec wrappers and the quickshell
    #    autostart both hardcode it.
    grep -rIl -e "/usr/bin/quickshell" -e "/usr/bin/uwsm-app" \
               -e "/usr/bin/xdg-terminal-exec" "$magikosDir" 2>/dev/null \
      | xargs -r sed -i \
        -e 's|/usr/bin/quickshell|quickshell|g' \
        -e 's|/usr/bin/uwsm-app|uwsm-app|g' \
        -e 's|/usr/bin/xdg-terminal-exec|xdg-terminal-exec|g'

    # --- Expose every script as a wrapped command --------------------------
    #
    # MAGIKOS_PATH must be set for the ~65 scripts that read it, and the runtime
    # deps must be on PATH even when invoked outside a login shell (systemd
    # units, quickshell, sway exec lines).
    depPath=${lib.makeBinPath runtimeDeps}
    for f in "$magikosDir"/bin/*; do
      [ -f "$f" ] || continue
      name=$(basename "$f")
      cat > "$out/bin/$name" <<EOF
    #!/usr/bin/env bash
    export MAGIKOS_PATH="$magikosDir"
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
}