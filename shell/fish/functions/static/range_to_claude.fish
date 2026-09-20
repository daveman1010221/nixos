function range_to_claude
    bat --no-pager --decorations always $argv[1] --line-range $argv[2]:$argv[3] | wl-copy
end
