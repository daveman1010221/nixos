function nixos_commit --description 'Secure commit: scrub secrets, commit if needed, restore, and verify'
    set -l json_file /boot/secrets/flakey.json
    set -l flake_file /etc/nixos/flake.nix

    echo "[nixos_commit] Mounting boot volume..."
    boot_is_mounted; or boot_toggle_mounts
    if test $status -ne 0
        echo "[nixos_commit] Failed to mount boot. Aborting."
        return 1
    end

    echo "[nixos_commit] Scrubbing secrets from flake.nix..."
    unfuck_purity $json_file $flake_file

    if git -C /etc/nixos diff --quiet --exit-code
        echo "[nixos_commit] No changes to commit. Continuing..."
    else
        if status --is-interactive
            echo -n "[nixos_commit] Enter commit message: "
            read -l commit_message
            if test -z "$commit_message"
                echo "[nixos_commit] No commit message entered. Aborting."
                fuck_purity $json_file $flake_file
                return 1
            end
        else
            echo "[nixos_commit] Non-interactive shell — using default commit message."
            set commit_message "automated hook commit"
        end

        echo "[nixos_commit] Committing clean flake.nix..."
        git -C /etc/nixos add flake.nix
        git -C /etc/nixos commit -m "$commit_message"
    end

    echo "[nixos_commit] Restoring secret values into flake.nix..."
    fuck_purity $json_file $flake_file

    echo "[nixos_commit] Unmounting boot volume..."
    boot_toggle_mounts

    return 0
end
