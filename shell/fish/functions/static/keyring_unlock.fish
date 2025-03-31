function keyring_unlock --description="unlocks the gnome keyring from the shell"
    read -s -P "Password: " pass
    for m in (echo -n $pass | gnome-keyring-daemon --replace --unlock)
        export $m
    end
    set -e pass
end
