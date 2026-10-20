{ config, lib, pkgs, ... }:

let
  cfg = config.home-magikos;
  magikosPackage = cfg.package;
  magikosConfig = "${magikosPackage}/share/magikos/config";

  # ~/.config/magikos is deliberately NOT managed from the package. It is
  # per-user runtime state -- installed plugins, chosen themes, shell.json
  # layout, and ~150M of wallpapers -- and symlinking the packaged baseline
  # over it would destroy all of that. It stays hand-managed; see the
  # `dotfiles/` escape hatch below if you want to version it.
  skipFromPackage = [ "magikos" ];

  # Built with an explicit listToAttrs rather than lib.mapAttrs': the latter
  # wraps each result in a { name, value } pair, which collides with the `name`
  # key of the configFile submodule.
  entriesFrom = dir:
    map (n: {
      name = n;
      value = { source = "${dir}/${n}"; };
    })
      (lib.filter (n: !(lib.elem n skipFromPackage))
        (lib.attrNames (builtins.readDir dir)));

  packagedConfig = builtins.listToAttrs (entriesFrom magikosConfig);

  # Optional local overrides, dropped into ./dotfiles/<name> in this repo.
  # Anything here wins over the packaged baseline. This is the supported place
  # to version personal files such as ~/.config/magikos.
  localOverrides =
    if builtins.pathExists ./dotfiles then
      builtins.listToAttrs (
        map (n: {
          name = n;
          value = { source = ./dotfiles/${n}; };
        }) (lib.attrNames (builtins.readDir ./dotfiles))
      )
    else
      { };
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
  };

  config = lib.mkIf cfg.enable {
    home.username = lib.mkDefault "magikxiii";
    home.homeDirectory = lib.mkDefault "/home/magikxiii";
    home.stateVersion = lib.mkDefault "26.11";

    # Only the state directory is pre-created. ~/.config/sway deliberately is
    # not: `xdg.configFile` links the whole packaged sway tree as a *single*
    # symlink, so a real directory sitting in the way makes linkGeneration fail
    # with "cannot overwrite directory" and the entire activation aborts. The
    # symlink is in place before any session starts, which is all Sway needs.
    home.activation.createConfigDirs = lib.mkBefore ''
        mkdir -p "$HOME/.local/state/magikos/toggles"

        # ~/.config/magikos is seeded rather than linked. Linking the packaged
        # tree over it is what skipFromPackage deliberately avoids: it is
        # per-user state -- installed plugins, chosen theme, shell.json layout,
        # wallpapers -- and a symlink would make all of it read-only in the
        # store and destroy the rest on first activation.
        #
        # But not seeding it at all is just as broken: on a fresh install the
        # directory never exists, and the QuickShell bar launched from sway's
        # autostart.conf comes up against a missing config and exits. So copy
        # the packaged baseline in exactly once and never touch it again. After
        # this runs the directory is user-owned, matching the Arch layout.
        if [ ! -e "$HOME/.config/magikos" ]; then
          mkdir -p "$HOME/.config"
          cp -r "${magikosConfig}/magikos" "$HOME/.config/magikos"
          chmod -R u+w "$HOME/.config/magikos"
        fi
    '';

    xdg.configFile = packagedConfig // localOverrides;
  };
}
