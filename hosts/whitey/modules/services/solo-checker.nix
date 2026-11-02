{ pkgs, ... }:

# Solo checker: silent when the SoloKeys Solo 2 is on the USB bus at login, loud when it is not.
#
# On 2026-10-25 and 2026-11-02 the Solo 2 (on the chipset's USB 2.0 controller, port 1) wedged: it stopped answering
# enumeration (`device descriptor read/64, error -110`, `device not accepting address, error -71`), so it was plugged in
# and nowhere to be found. A restart does not clear that: the board keeps its USB ports powered through a reboot, and
# no controller here can switch a port's power from software (PPC=0, no ACPI power resources on any port). Pulling it
# out and plugging it back in does, and so does a shutdown with ErP enabled in the firmware.
let
  vendor  = "1209";   # SoloKeys
  product = "beee";   # Solo 2 Security Key

  check = pkgs.writeShellApplication {
    name = "solo-checker";
    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.libnotify pkgs.systemd ];
    text = ''
      present() {
        local d
        for d in /sys/bus/usb/devices/*; do
          [ -r "$d/idVendor" ] && [ -r "$d/idProduct" ] || continue
          if [ "$(cat "$d/idVendor")" = "${vendor}" ] && [ "$(cat "$d/idProduct")" = "${product}" ]; then
            return 0
          fi
        done
        return 1
      }

      # Some grace: at login it may still be enumerating.
      for _ in $(seq 1 20); do
        if present; then exit 0; fi
        sleep 1
      done

      # Plugged in but not answering, or not plugged in at all: the kernel's log tells them apart. grep reads it all
      # (no -q): stopping at the first match would kill journalctl with SIGPIPE, which pipefail counts as no match.
      if journalctl -k -b --no-pager -q 2>/dev/null \
          | grep -E 'usb [0-9]+-[0-9.]+: (device descriptor read|device not accepting address|Device not responding to setup address)' >/dev/null; then
        body="A USB device is plugged in but not answering: most likely the Solo 2, wedged. Pull it out and plug it back in. A restart will not reset it: the port stays powered."
      else
        body="It is not on the USB bus. If it is plugged in, it may be wedged: pull it out and plug it back in."
      fi
      echo "Solo 2 not found. $body" >&2

      # The notification daemon may come up a little after the session starts.
      for _ in $(seq 1 30); do
        if notify-send --urgency=critical --app-name="Solo checker" --icon=dialog-warning \
            "Solo 2 security key not found" "$body"; then
          exit 1
        fi
        sleep 2
      done
      exit 1
    '';
  };
in
{
  systemd.user.services.solo-checker = {
    description = "Check that the SoloKeys Solo 2 is on the USB bus";
    wantedBy = [ "graphical-session.target" ];
    after    = [ "graphical-session.target" ];
    partOf   = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${check}/bin/solo-checker";
    };
  };
}
