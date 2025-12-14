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
  
    bumblebee.enable = false;
  
    nvidiaOptimus.disable = false;
    nvidia = {
      gsp.enable = true;
      prime = {
        allowExternalGpu = false;
        offload.enable = false; # Mutually exclusive with prime sync.
        offload.enableOffloadCmd = false;
        sync.enable = false;
        nvidiaBusId = "PCI:1:0:0";
        intelBusId = "PCI:0:2:0";
        reverseSync.enable = false;
      };
  
      #dynamicBoost.enable = true;
  
      open = false;
  
      # Modesetting is required.
      modesetting.enable = true;
  
      # Nvidia power management. Experimental, and can cause sleep/suspend to
      # fail. Enable this if you have graphical corruption issues or
      # application crashes after waking up from sleep. This fixes it by saving
      # the entire VRAM memory to /tmp/ instead of just the bare essentials.
      powerManagement.enable = true;
  
      # Fine-grained power management. Turns off GPU when not in use.
      # Experimental and only works on modern Nvidia GPUs (Turing or newer).
      powerManagement.finegrained = false;
  
      # Enable the Nvidia settings menu,
      # accessible via `nvidia-settings`.
      nvidiaSettings = true;
  
      # Optionally, you may need to select the appropriate driver version for
      # your specific GPU.
      # package = config.boot.kernelPackages.nvidiaPackages.beta;
      package = config.boot.kernelPackages.nvidia_x11_beta;
    };
  
    nvidia-container-toolkit = {
      enable = true;
    };
  };
}
