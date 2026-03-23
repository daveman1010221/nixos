{ config, lib, pkgs, ... }:

{
  # Base configuration: both GPUs are available, but the dGPU is primary
  # (adjust if your host already has settings; we'll just define the specialisations)

  specialisation = {
    # Normal desktop profile – uses dGPU for display and development
    normal = {
      inheritParentConfig = true;  # start from the main config
      configuration = {
        # Ensure the dGPU is the primary display device.
        # The driver order can influence which card is used first.
        services.xserver.videoDrivers = lib.mkForce [ "amdgpu" "modesetting" ];

        # Optionally set environment variables to hint applications toward the dGPU
        environment.sessionVariables = {
          DRI_PRIME = "1";   # 1 = use dGPU for rendering where possible
        };

        # If you use Wayland (COSMIC), it should automatically pick the primary GPU
        # based on the kernel's DRM device order. The dGPU is often card1, but
        # the display manager will use the card connected to the monitor.
        # If your monitor is connected to the dGPU, this profile works as‑is.
      };
    };

    # Container work profile – use iGPU for display, dGPU exclusively for compute
    container = {
      inheritParentConfig = true;
      configuration = {
        # Prefer the modesetting driver (generic) which works well for the iGPU,
        # and put amdgpu second.
        services.xserver.videoDrivers = lib.mkForce [ "modesetting" "amdgpu" ];

        # Unset DRI_PRIME or set it to 0 to avoid offloading to dGPU
        environment.sessionVariables = {
          DRI_PRIME = "0";
        };

        # Optional: blacklist the dGPU from being used by Xorg/Wayland
        # by adding a custom Xorg configuration that excludes its PCI bus.
        # This is advanced and usually not needed if you physically connect
        # your monitor to the iGPU's port.
      };
    };
  };
}
