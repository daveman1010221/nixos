function detect_secrets_leaked --description 'Scan flake.nix for committed secrets'
    set -l flake_file $argv[1]

    set -l matches (grep -E 'PLACEHOLDER_.*= *"[^"]+"' $flake_file | grep -v '="";')

    if test -n "$matches"
        echo "$matches"
        return 1  # ❌ Secrets found — block the push
    else
        return 0  # ✅ No secrets — allow the push
    end
end
