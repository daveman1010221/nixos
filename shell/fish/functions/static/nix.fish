function nix
    if contains -- "flake" $argv && contains -- "update" $argv
        if test (pwd) = "/etc/nixos"
            echo "🔒 Running flake_backup first..."
            flake_backup
            # Note: 'nix flake update' won't update nixpkgs reliably.
            # Run 'nix flake update nixpkgs' explicitly if needed.
        end
    end
    command nix $argv
end
