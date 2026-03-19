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

    nvidia = {
      # Use the open kernel modules — correct for RTX 4000 Ada (AD104).
      open = true;

      # Keep drivers in sync with the kernel package set.
      package = config.boot.kernelPackages.nvidiaPackages.stable;

      # iGPU drives the display; dGPU is only woken for offloaded workloads.
      prime = {
        offload = {
          enable = true;
          enableOffloadCmd = true;  # gives you `nvidia-offload <cmd>`
        };

        # lspci shows:
        #   00:02.0  Intel Raptor Lake-S UHD Graphics  → Bus 0, Device 2, Function 0
        #   01:00.0  NVIDIA AD104GLM RTX 4000 Ada      → Bus 1, Device 0, Function 0
        intelBusId  = "PCI:0:2:0";
        nvidiaBusId = "PCI:1:0:0";
      };

      # Don't let the nvidia driver touch power management — let the iGPU
      # handle suspend/resume. Fine-Power-Management is safe on Ada with open modules.
      powerManagement = {
        enable = false;
        finegrained = false;
      };

      modesetting.enable = true;
      nvidiaSettings = false;  # GUI settings app — not useful in this setup
    };

    keyboard.qmk.enable = true;

    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
  };
}
