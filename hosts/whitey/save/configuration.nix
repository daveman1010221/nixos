{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  nixpkgs.config.allowUnfree = true;

  boot.loader.grub = {
    enable = true;
    version = 2;
    efiSupport = true;
    devices = [ "nodev" ];
    efiInstallAsRemovable = false;
  };
  boot.loader.systemd-boot.enable = false;


  boot.loader.efi.efiSysMountPoint = "/boot/EFI";
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelModules = [ "r8125" ];
  boot.extraModulePackages = with config.boot.kernelPackages; [
    r8125
  ];
  boot.blacklistedKernelModules = [ "r8169" ];

  hardware.sensor.iio.enable = true;
  hardware.sensor.hddtemp.enable = true;
  hardware.sensor.hddtemp.drives = [ "/dev/disk/by-path/pci-0000:01:00.0-nvme-1" ];
  services.hardware.openrgb.enable = true;
  services.hardware.openrgb.motherboard = "amd";

  networking.hostName = "whitey";
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  # services.xserver.displayManager.gdm.enable = true;
  # services.xserver.desktopManager.gnome.enable = true;
  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;
  
  users.users.djshepard = {
    isNormalUser = true;
    initialPassword = "foobar";
    shell = pkgs.fish;
    extraGroups = [ "wheel" "networkmanager" ];
    # packages = with pkgs; [
    # ];
  };

  users.users.root = {
    initialPassword = "foobar";
  };

  programs.firefox.enable = true;
  programs.fish.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    bottom
    fish
    lm_sensors      # Base for temperature/voltage/fan readings
    nvme-cli        # NVMe SSD temperature and health
    hddtemp         # HDD temperature (requires SMART support)
    smartmontools   # SMART data (for both HDD and SSD)
    glances         # Terminal system monitor with sensor support
    neovim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    openrgb-with-all-plugins
    watch           # For `watch -n 1 sensors`
    wget
  ];

  environment.sessionVariables.COSMIC_DATA_CONTROL_ENABLED = 1;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  systemd.packages = [ pkgs.observatory ];
  #systemd.services.monitord.wantedBy = [ "multi-user.target" ];

  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  system.stateVersion = "25.05"; # Did you read the comment?
}
