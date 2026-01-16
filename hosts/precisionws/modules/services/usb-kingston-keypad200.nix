{ ... }:
{
  services.udev.extraRules = ''
    # Kingston Keypad200 (2009:7200) - prevent autosuspend
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="2009", ATTR{idProduct}=="7200", \
      ATTR{power/control}="on", ATTR{power/autosuspend_delay_ms}="-1"
  '';
}
