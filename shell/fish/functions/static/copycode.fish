function copycode
    # Default extensions if none given
    set -l exts $argv
    if test (count $exts) -eq 0
        set exts rs nix toml
    end

    # Build fd args dynamically
    set -l fd_args
    for e in $exts
        set fd_args $fd_args -e $e
    end

    # Run fd → bat → sed → wl-copy
    fd $fd_args -0 \
            | xargs -0 bat --color=always --style=header --paging=never \
            | sed -r 's/\x1B\[[0-9;]*[mK]//g' \
            | wl-copy
end
