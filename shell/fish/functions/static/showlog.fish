function showlog --description="journalctl with some niceties for realtime viewing"
    journalctl -xf --no-hostname
end
