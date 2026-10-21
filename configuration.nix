{ config, lib, pkgs, ... }:

{
  imports = [
    ./nix/module.nix
    ./nix/parity.nix
  ];

  magikos.enable = true;

  # Bootloader (source used Limine; systemd-boot is the NixOS default that supports btrfs)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Locale / time
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Networking
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  services.resolved.enable = true;

  # Firmware / microcode (AMD)
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.amd.updateMicrocode = true;

  # Graphics (AMD + 32-bit for gaming)
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  # Sound (PipeWire)
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };
  services.pulseaudio.enable = false;

  # Bluetooth
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # Power / disks
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;
  services.udisks2.enable = true;
  services.fstrim.enable = true;

  # Virtualisation
  virtualisation.libvirtd.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  # Ollama
  services.ollama.enable = true;

  # Display manager + WM
  # SDDM asserts that either services.xserver.enable or the experimental
  # sddm.wayland.enable is true. Enable the xserver module (this also provides
  # XWayland, which Sway needs for X11 apps) instead of the weston/kwin greeter.
  services.xserver = {
    enable = true;
    xkb.layout = "us";
  };
  services.displayManager.sddm.enable = true;
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    xwayland.enable = true;
  };

  # XDG portals
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [ xdg-desktop-portal-gtk xdg-desktop-portal-wlr ];
  };

  # Desktop apps integration
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };
  programs.gamemode.enable = true;
  programs.fish.enable = true;
  programs.zsh.enable = true;
  programs.neovim.enable = true;

  # Unfree packages (steam, brave, etc.)
  nixpkgs.config.allowUnfree = true;

  # Shell default
  users.users.magikxiii = {
    isNormalUser = true;
    description = "magikxiii";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" "storage" "lp" "rfkill" "libvirtd" ];
    shell = pkgs.fish;
  };

  # Polkit
  security.polkit.enable = true;

  # The account below is created without a password, so sudo must not ask for
  # one. nixpkgs defaults security.sudo.wheelNeedsPassword to true, which
  # would leave every privileged operation -- nixos-rebuild, mounting disks,
  # running the MagikOS pkg backend -- asking for a password that cannot be
  # entered. The previous /etc/sudoers carried a passwordless wheel rule
  # that this configuration did not generate, so a rebuild silently dropped it.
  security.sudo.wheelNeedsPassword = false;

  # ssh
  services.openssh.enable = true;

  # flatpak
  services.flatpak.enable = true;

  # zram configured in hardware-configuration.nix

  # Packages
  environment.systemPackages = with pkgs; [
    # core
    git curl wget unzip unrar rsync which less nano micro neovim fish zsh bash-completion
    # system tools
    sudo efibootmgr efivar linux-firmware ethtool hdparm smartmontools lvm2 cryptsetup mdadm dmidecode
    dosfstools exfatprogs e2fsprogs xfsprogs btrfs-progs f2fs-tools ntfs3g
    inotify-tools lsscsi usbutils wirelesstools iw wpa_supplicant
    # networking
    networkmanager networkmanager-openvpn openvpn iwd dnsmasq modemmanager
    # audio
    pipewire wireplumber pavucontrol
    # bluetooth
    # wayland / sway
    sway swaybg wmenu fuzzel foot kitty ghostty alacritty tmux
    wl-clipboard wtype wlsunset playerctl brightnessctl
    flameshot swappy grim slurp
    # files
    thunar udiskie
    # terminals multiplexers
    fastfetch btop glances mission-center
    # web
    brave chromium firefox
    # The MagikOS browser keybinding launches `brave-origin`, which on the
    # Arch system is the brave-origin-bin AUR package. There is no nixpkgs
    # equivalent of that build, so the name is provided here over the stock
    # brave package: the binding resolves here instead of failing with
    # "command not found", and the window that opens is the same browser the
    # rest of the system already has.
    #
    # It ships a desktop entry too, so that it is a browser in its own
    # right rather than only a command: `magikos default browser
    # brave-origin` writes brave-origin.desktop as the XDG default, and
    # without the entry that default would name a file that does not exist.
    (pkgs.runCommand "brave-origin" { } ''
      mkdir -p "$out/bin" "$out/share/applications"

      cat > "$out/bin/brave-origin" <<EOF
      #!${pkgs.bash}/bin/bash
      exec ${pkgs.brave}/bin/brave "$@"
      EOF
      chmod +x "$out/bin/brave-origin"

      cat > "$out/share/applications/brave-origin.desktop" <<EOF
      [Desktop Entry]
      Version=1.0
      Name=Brave Origin
      GenericName=Web Browser
      Exec=brave-origin %U
      Terminal=false
      Type=Application
      Icon=brave-browser
      Categories=Network;WebBrowser;
      MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
      StartupWMClass=Brave
      Keywords=web;browser;internet;
      EOF
    '')
    # media
    mpv vlc ffmpeg gst_all_1.gst-libav gst_all_1.gst-plugins-bad gst_all_1.gst-plugins-ugly
    imagemagick feh imv
    # dev tools
    mise
    opencode
    # dev
    gcc clang cmake meson ninja scdoc pkg-config
    python3 python3Packages.pip nodejs rustc cargo go lua luajit
    ripgrep fd jq yq
    # virtualisation
    qemu libvirt virt-manager
    # gaming
    steam gamemode gamescope mangohud goverlay vulkan-tools vulkan-headers mesa-demos
    # utils
    zip zstd xz gzip
    gum fzf zoxide lsd eza bat tree
    # nix tooling
    nix-output-monitor nvd
  ];

  # Fonts
  fonts.packages = with pkgs; [
    noto-fonts noto-fonts-cjk-sans noto-fonts-color-emoji
    dejavu_fonts liberation_ttf nerd-fonts.jetbrains-mono
    font-awesome
  ];
  fonts.fontconfig.enable = true;

  # /bin/bash and /usr/bin/python3
  #
  # NixOS only ships /bin/sh. The package rewrites the shebangs of everything
  # in the MagikOS tree, but /bin/bash is also what anything else on the
  # system assumes: packaging helpers, installer scripts and third-party
  # software all hardcode it, and they fail with "bad interpreter" when it is
  # missing.
  #
  # The same is true of /usr/bin/python3, which five scripts in the tree use.
  # The package rewrites those too, but the test suite runs the scripts
  # straight out of a git checkout, where the shebangs are still the
  # originals.
  #
  # nixpkgs creates /bin/sh the same way; this mirrors that for the two
  # interpreters MagikOS assumes.
  system.activationScripts.binbash = lib.stringAfter [ "stdio" ] ''
    mkdir -p /bin
    chmod 0755 /bin
    ln -sfn "${pkgs.bash}/bin/bash" /bin/.bash.tmp
    mv /bin/.bash.tmp /bin/bash # atomically replace /bin/bash

    mkdir -p /usr/bin
    chmod 0755 /usr/bin
    ln -sfn "${pkgs.python3}/bin/python3" /usr/bin/.python3.tmp
    mv /usr/bin/.python3.tmp /usr/bin/python3 # atomically replace /usr/bin/python3

    # sleep is called by absolute path from the stubs the hardware tests
    # install, which stand in for a blocking supergfxctl.
    ln -sfn "${pkgs.coreutils}/bin/sleep" /usr/bin/.sleep.tmp
    mv /usr/bin/.sleep.tmp /usr/bin/sleep # atomically replace /usr/bin/sleep
  '';

  # Nix
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;

  system.stateVersion = "26.11";
}
