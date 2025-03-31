function do_startup --description="Call this from an interacive shell at startup to set the environment per interactive preferences."
    set -l container_count (count (docker ps -q))
    if test $container_count -gt 0
        docker stop (docker ps -q)
    end
    echo 2013266 | doas tee /proc/sys/vm/min_free_kbytes
    echo 1 | doas tee /proc/sys/vm/swappiness
    hostname_update
end
