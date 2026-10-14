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

    # Sway's include list is written with an explicit ~/.config/sway/... path
    # per file, so the tree has to exist before the compositor reads it.
    home.activation.createConfigDirs = lib.mkBefore ''
        mkdir -p "$HOME/.config/sway" "$HOME/.local/state/magikos/toggles"
    '';

    xdg.configFile = packagedConfig // localOverrides;
  };
}