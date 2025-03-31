function tmp_toggle_immutable --description="It's good to keep immutable tmp filesystem, unless it isn't."
    if tmp_is_immutable "quiet"
        doas mount -o remount rw /tmp
    else
        doas mount -o remount ro /tmp
    end
end
