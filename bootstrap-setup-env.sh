#!/usr/bin/env bash

set -euo pipefail

echo "[INFO] Enabling flake and nix-command support"
export NIX_CONFIG="experimental-features = nix-command flakes"

echo "[INFO] Installing essential packages with nix profile"
nix profile install \
  github:NixOS/nixpkgs#kitty \
  github:NixOS/nixpkgs#fish \
  github:NixOS/nixpkgs#ripgrep \
  github:NixOS/nixpkgs#tree \
  github:daveman1010221/nix-neovim || true

echo "[INFO] Creating /etc/shells if missing and adding valid shells"
sudo tee /etc/shells > /dev/null <<EOF
/run/current-system/sw/bin/sh
/run/current-system/sw/bin/bash
$(which fish)
/run/current-system/sw/bin/zsh
EOF

echo "[INFO] Setting Fish as default shell"
chsh -s "$(which fish)"

echo "[INFO] Writing Fish configuration to ~/.config/fish/config.fish"
mkdir -p ~/.config/fish
cat > ~/.config/fish/config.fish <<'EOF'
if status is-interactive
    set -gx EDITOR nvim
    set -gx VISUAL nvim
    fish_vi_key_bindings
end
EOF

echo "[INFO] Configuring Git identity"
git config --global user.name "David Shepard"
git config --global user.email "daveman1010220@gmail.com"

echo "[INFO] Setting up Git credential storage"

read -rp "GitHub username: " GH_USER
read -rsp "GitHub personal access token: " GH_TOKEN
echo

cat > ~/.git-credentials <<EOF
https://${GH_USER}:${GH_TOKEN}@github.com
EOF

chmod 600 ~/.git-credentials
git config --global credential.helper store

echo "[INFO] Git credentials stored in ~/.git-credentials"

echo "[DONE] Basic shell environment is now set up."
echo "Restart your shell or run 'exec fish' to activate."
