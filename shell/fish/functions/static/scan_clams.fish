function scan_clams --description 'Run clamscan with some sane arguments'
    sudo -v && set locations /bin /boot /etc /home /lib /lib64 /lost+found /nix /root /srv /tmp /usr /var

    for n in $locations
        # This is wicked. We're going to create a named pipe and
        # start reading from it, then write the named pipe output
        # to systemd-cat, which will ensure the clamscan
        # output ends up in the systemd journal. We then fork
        # this pipeline to the background, kick off the
        # actual scan, and tee the scan results to the
        # terminal and the named pipe. The pipe waits for
        # input in the background, one per scan, until that
        # scan starts producing results. When the scan goes
        # out of scope, the inode for the fifo is cleaned up,
        # since the file was already deleted in the
        # foreground by the script. This ends up spawning
        # four processes per scan, but it's entirely fine.

        set suffix (printf '%06X' (random))

        set fifo "/tmp/clamfifo.$suffix"
        mkfifo $fifo

        cat $fifo | systemd-cat -t clamscan[$n] -p info &

        set cat_pid $last_pid

        sudo clamscan -r --infected --bell $n | tee $fifo &

        rm $fifo
    end
end
