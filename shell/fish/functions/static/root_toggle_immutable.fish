function root_toggle_immutable --description="It's good to keep immutable root filesystem, unless it isn't."
    if root_is_immutable "quiet"
        doas mount -o remount rw /
    else
        doas mount -o remount ro /
    end
end
