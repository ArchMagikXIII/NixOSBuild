{ config, lib, pkgs, ... }:

let
  cfg = config.home-magikos;
  magikosPackage = cfg.package;
  magikosConfig = "${magikosPackage}/share/magikos/config";

  # Top-level entries of the packaged config tree. MagikOS ships these as the
  # defaults for a new user; on Arch they are seeded into ~/.config from
  # /etc/skel and not touched again, with share/magikos/config kept around as
  # the resync source. See the activation script below.
  packagedEntries = builtins.attrNames (builtins.readDir magikosConfig);

  # Local overrides, dropped into ./dotfiles/<name> in this repo. Anything
  # here wins over the packaged baseline.
  #
  # These are symlinks into this repository rather than into the store. A
  # store-backed symlink -- which is what Home Manager's xdg.configFile
  # produces -- is read-only, so every tweak of a keybinding would need a
  # rebuild, and it is the read-only tree that the "seed real files" change
  # below was written to get away from. Pointing at the checkout instead means
  # the live config can be edited in place, the edit is version-controlled at
  # the same time, and `git diff` in this repository shows exactly what
  # changed on the desktop.
  dotfilesDir = ./dotfiles;
  dotfileEntries = builtins.attrNames (builtins.readDir dotfilesDir);

  # Packaged entries that are not managed by ./dotfiles. A dotfile wins: the
  # seeding below deletes a symlink before it copies, so it would tear the
  # dotfile link down and put a copy of the package version back.
  seededEntries = builtins.filter (n: !(builtins.elem n dotfileEntries)) packagedEntries;
in
{
  options.home-magikos = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Deploy the packaged MagikOS config tree into ~/.config. On by default,
        since importing this module is already the opt-in.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.magikos;
      defaultText = lib.literalExpression "pkgs.magikos";
      description = "The MagikOS package whose share/magikos/config is deployed.";
    };

    dotfilesPath = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/Projects/*/hosts/dotfiles";
      description = ''
        The directory the dotfiles are symlinked from.

        The default points at the live checkout of this repository, so an edit
        takes effect as soon as it is saved and shows up in `git diff` here
        rather than living only on the machine. $HOME and the glob are
        expanded by the activation script, so the path is not tied to one
        account and a checkout in another directory under ~/Projects is
        found too. Point it elsewhere if the checkout lives somewhere else;
        when no candidate is there the packaged copy is used instead, so the
        session still comes up.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.username = lib.mkDefault "magikxiii";
    home.homeDirectory = lib.mkDefault "/home/magikxiii";
    home.stateVersion = lib.mkDefault "26.11";

    # Seed the packaged config tree into ~/.config as real, writable files.
    #
    # Symlinking it into the store -- which is what this replaces -- does not
    # work, because the store is read-only and applications write inside their
    # own config directories: fish cannot save universal variables, fcitx5
    # cannot write its profile, chromium cannot save Preferences, and opencode
    # exits on startup when it writes service-prod.json. Linking the *files*
    # instead of the directories only moves the problem, since anything that
    # rewrites a file in place still gets EROFS.
    #
    # Upstream seeds /etc/skel/.config as copies and never re-copies afterwards,
    # keeping share/magikos/config as the resync source. Match that: copy once,
    # only when the target is absent, and leave user edits alone. Delete
    # ~/.config/<name> to take the packaged version again.
    #
    # A symlink left behind by an older activation is removed first, so
    # existing installs heal instead of staying on the read-only path. Ordering
    # against linkGeneration is explicit because this must run before it, not
    # after a link has already been created.
    home.activation.createConfigDirs =
      lib.hm.dag.entryBefore [ "linkGeneration" ] ''
        mkdir -p "$HOME/.config" "$HOME/.local/state/magikos/toggles"

        for entry in ${lib.concatStringsSep " " seededEntries}; do
          target="$HOME/.config/$entry"
          if [ -L "$target" ]; then
            rm -f "$target"
          fi
          if [ ! -e "$target" ]; then
            cp -r "${magikosConfig}/$entry" "$target"
            chmod -R u+w "$target"
          fi
        done
      '';

    # The guest-side recovery script goes into ~/.local/bin rather than the
    # system profile, because ~/.local/bin survives a boot onto the wrong
    # profile: the system profile is rebuilt from whatever was booted, so a
    # script that only existed in the intended profile would be gone exactly
    # when it is needed.
    home.activation.installVmSync =
      lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        mkdir -p "$HOME/.local/bin"
        install -Dm755 ${../bin/magikos-vm-sync} "$HOME/.local/bin/magikos-vm-sync"
      '';

    # Symlink the dotfiles into ~/.config.
    #
    # Runs after linkGeneration so it wins over anything the seeding above
    # did. A real directory that used to live at the target is moved aside
    # rather than deleted, so the first run does not throw the seeded copy
    # away, and a target that is already the right symlink is left alone so
    # repeated rebuilds do not churn it.
    home.activation.linkDotfiles =
      lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        mkdir -p "$HOME/.config"

        for entry in ${lib.concatStringsSep " " dotfileEntries}; do
          target="$HOME/.config/$entry"

          # The live checkout is preferred over this flake's own copy, which
          # lives in the read-only store: pointing at the checkout means an
          # edit is live as soon as it is saved, and it is version-controlled
          # here at the same time.
          source=""
          for pattern in ${cfg.dotfilesPath}; do
            for candidate in $pattern; do
              if [ -d "$candidate/$entry" ]; then
                source="$candidate/$entry"
                break 2
              fi
            done
          done
          if [ -z "$source" ] && [ -d "${dotfilesDir}/$entry" ]; then
            source="${dotfilesDir}/$entry"
          fi
          [ -n "$source" ] || continue

          if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
            continue
          fi

          if [ -e "$target" ] || [ -L "$target" ]; then
            backup="$target.hm-backup"
            rm -rf "$backup"
            mv "$target" "$backup"
            echo "Moved $target aside to $backup" >&2
          fi

          ln -sfn "$source" "$target"
        done
      '';
  };
}
