{ hostPkgs, ... }:

{
  services.xserver = {
    enable = true;

    excludePackages = with hostPkgs; [ xterm ];

    # nvidia must be listed first — it installs the PRIME dispatch glue.
    # modesetting is the iGPU driver that actually drives the display.
    videoDrivers = [ "nvidia" "modesetting" ];
  };
}
