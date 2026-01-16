{ config, pkgsForHost, ... }:

{
  hardware = {
    enableAllFirmware = true;
    enableAllHardware = true;
    cpu.intel.updateMicrocode = true;
    cpu.x86.msr.enable = true;
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgsForHost; [
        libva
        libvdpau
        libglvnd
        mesa
      ];
    };
  
    # Effectively, this option adds udev rules that allow a
    # non-privileged user to modify keyboard firmware.
    keyboard.qmk.enable = true;
  
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
  };
}
