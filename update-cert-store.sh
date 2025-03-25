#!/usr/bin/env bash

set -e

CERT_DIR="/etc/secrets"
STORE_PATH_FILE="/etc/secrets/nix-store-paths"

update_store_path() {
    local file="$1"
    if [[ -f "$file" ]]; then
        STORE_PATH=$(nix store add-path "$file")
        echo "$STORE_PATH"  # Return the new store path
    else
        echo "ERROR: Missing file: $file" >&2
        exit 1
    fi
}

echo "Updating Nix store paths for kernel certs..."

MOK_PEM_PATH=$(update_store_path "$CERT_DIR/MOK.pem")
MOK_PRIV_PATH=$(update_store_path "$CERT_DIR/MOK.priv")

# Write updated paths to a file that flake.nix can read
echo "MOK_PEM_PATH=$MOK_PEM_PATH" > "$STORE_PATH_FILE"
echo "MOK_PRIV_PATH=$MOK_PRIV_PATH" >> "$STORE_PATH_FILE"

echo "Updated Nix store paths:"
cat "$STORE_PATH_FILE"
