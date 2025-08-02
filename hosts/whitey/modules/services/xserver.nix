{ hostPkgs, ... }:

{
  services.xserver = {
    # Required for DE to launch.
    enable = true;

    # Exclude default X11 packages I don't want.
    excludePackages = with hostPkgs; [ xterm ];

    # Load nvidia driver for Xorg and Wayland
    videoDrivers = ["amdgpu"];
  };
}
