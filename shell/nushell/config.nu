# shell/nushell/config.nu
# Nushell configuration

# Remove welcome banner
$env.config.show_banner = true

let starship_dir = ($nu.data-dir | path join "vendor/autoload")
let starship_file = ($starship_dir | path join "starship.nu")

if not ($starship_file | path exists) {
  mkdir $starship_dir
  starship init nu | save -f $starship_file
}

# Atuin integration
let atuin_bin = (which atuin | get 0.path? | default "")
if ($atuin_bin != "") {
  let init_path = "~/.local/share/atuin"
  if not ($init_path | path exists) {
    mkdir ($init_path | path dirname)
    ^$atuin_bin init nu | save $init_path
  }

  # You must make this file exist before this will parse correctly.
  # I.e.,
  # atuin init nu > ~/.local/share/atuin/init.nu

  source ~/.local/share/atuin/init.nu

} else {
  $env.config.history.file_format = "sqlite"
  $env.config.history.max_size = 10000
}

# Vi‑mode keybindings
$env.config.edit_mode = "vi"

# Syntax highlighting colours (Gruvbox)
$env.config.color_config = {
  separator: { fg: "#ebdbb2" }
  leading_trailing_space_bg: { bg: "#282828" }
  header: { fg: "#b8bb26" }
  date: { fg: "#fe8019" }
  filesize: { fg: "#83a598" }
  row_index: { fg: "#fabd2f" }
  bool: { fg: "#b8bb26" }
  int: { fg: "#ebdbb2" }
  duration: { fg: "#ebdbb2" }
  range: { fg: "#ebdbb2" }
  float: { fg: "#ebdbb2" }
  string: { fg: "#ebdbb2" }
  nothing: { fg: "#fb4934" }
  binary: { fg: "#ebdbb2" }
  cellpath: { fg: "#ebdbb2" }
  hints: { fg: "#928374" }
}

# Aliases - simple command calls only
alias lh = eza --group --header --group-directories-first --long --icons --git --all --binary --dereference --links

plugin add /run/current-system/sw/bin/nu_plugin_gstat
plugin add /run/current-system/sw/bin/nu_plugin_query
plugin add /run/current-system/sw/bin/nu_plugin_formats
plugin add /run/current-system/sw/bin/nu_plugin_skim
plugin add /run/current-system/sw/bin/nu_plugin_semver
plugin add /run/current-system/sw/bin/nu_plugin_polars
