function do_startup --description="Call this from an interacive shell at startup to set the environment per interactive preferences."
    # set -l container_count (count (docker ps -q))
    # if test $container_count -gt 0
    # docker stop (docker ps -q)
    # end
    echo 1 | doas tee /proc/sys/vm/swappiness
    sudo systemctl stop fwupd.service
    # sudo systemctl stop expressvpn fwupd.service
    sudo cryptsetup luksClose /dev/mapper/boot_crypt
    # sudo systemctl start expressvpn fwupd.service
    sudo systemctl start fwupd.service
end
