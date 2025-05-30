{
  boot.loader = {
    efi.canTouchEfiVariables = false;
    efi.efiSysMountPoint = "/boot/EFI";
  
    # Enable the GRUB bootloader with UEFI support
    grub = {
      enable = true;
      enableCryptodisk = true;
      efiSupport = true;
      device = "nodev";
      efiInstallAsRemovable = true;
      copyKernels = true; # Ensures kernel/initrd are copied to the ESP, necessary for encrypted /boot
  
      # Setting 'extraGrubInstallArgs' with an encrypted boot completely breaks
      # 'enableCryptodisk'. This took a lot of time to figure out.
    };
  
    # Use the systemd-boot EFI boot loader.
    systemd-boot.enable = false;
  };
}
