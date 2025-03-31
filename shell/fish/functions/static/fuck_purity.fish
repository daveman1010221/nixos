function fuck_purity --description "Inject values from JSON into flake.nix, violating purity with extreme prejudice"
    set -l json_file $argv[1]
    set -l flake_file $argv[2]

    if not test -f $json_file
        echo "Missing JSON file: $json_file"
        return 1
    end

    if not test -f $flake_file
        echo "Missing flake.nix file: $flake_file"
        return 1
    end

    for key in (jq -r 'keys[]' $json_file)
        set value (jq -r --arg k $key '.[$k]' $json_file)

        sed -i "s|\($key *= *\)\"[^\"]*\"|\1\"$value\"|" $flake_file
    end
end
