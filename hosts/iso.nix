{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
    ../configuration.nix
  ];

  # The installation CD is a live image: it boots straight into a root shell on
  # tty1, so no display manager and no locked user account are needed. Pulling
  # in ../configuration.nix would otherwise try to enable SDDM against a locked
  # account and fail the CD build.
  services.displayManager.sddm.enable = lib.mkForce false;
  services.xserver.enable = lib.mkForce false;
  services.getty.autologinUser = lib.mkForce "root";

  # The live CD carries the flake so the installer can `nixos-install` from it
  # without network access to GitHub.
  environment.systemPackages = with pkgs; [ git ];

  # The HP x360 14 (Pentium N5000, Gemini Lake) needs the Intel DRM driver and
  # the firmware blobs for its integrated graphics. The minimal CD does not
  # ship them, so the live console would come up without KMS and the install
  # would have no display.
  boot.kernelModules = [ "i915" ];
  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;

  # The minimal CD ships no NetworkManager by default; enable it so the
  # installer can pull packages if the flake copy is missing.
  networking.networkmanager.enable = true;
  # Carry the flake on the CD so `nixos-install` can use it offline. Copy the
  # whole repo into /iso/NixOSBuild on the image.
  isoImage.contents = [
    {
      source = pkgs.runCommand "NixOSBuild-flake" { } "cp -r ${./.} $out";
      target = "/iso/NixOSBuild";
    }
  ];
}
