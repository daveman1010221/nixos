# shell/nushell/env.nu
# Environment variables for Nushell

# Re‑use system‑wide variables where possible
let nvim_path = (which nvim | get 0.path? | default "nvim")
$env.EDITOR = $nvim_path

let nu_path = (which nu | get 0.path? | default "nu")
$env.SHELL = $nu_path

$env.BROWSER = "/run/current-system/sw/bin/librewolf"
$env.MANPAGER = "sh -c 'col -bx | bat --language man --style plain'"
$env.BAT_THEME = "gruvbox-dark"

# Wayland environment
$env.NIXOS_OZONE_WL = 1
$env._JAVA_AWT_WM_NONREPARENTING = 1
$env.MOZ_ENABLE_WAYLAND = 1
$env.QT_QPA_PLATFORM = "wayland"
$env.SDL_VIDEODRIVER = "wayland"
$env.WLR_NO_HARDWARE_CURSORS = 1

# FZF environment (compatible with Nushell)
$env.FZF_DEFAULT_OPTS = "--prompt='🔭 ' --height 80% --layout=reverse --border"
$env.FZF_DEFAULT_COMMAND = "rg --files --no-ignore --hidden --follow --glob '!.git/'"
