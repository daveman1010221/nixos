function port_find_open --description="Finds an open upper port"
    # lower and upper port bounds borrowed from Bash.
    while :
        set PULSE_PORT (shuf -i 32768-60999 -n 1)
        ss -lpn | rg -q ":$PULSE_PORT " || break
    end
    echo $PULSE_PORT
end
