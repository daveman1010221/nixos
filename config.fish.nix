{ pkgs }:

let
  myFishConfig = ''
# /etc/fish/config.fish: DO NOT EDIT -- this file has been generated automatically.

# if we haven't sourced the general config, do it
if not set -q __fish_nixos_general_config_sourced
  source /etc/fish/shellInit.fish

  

  # and leave a note so we don't source this config section again from
  # this very shell (children will source the general config anew)
  set -g __fish_nixos_general_config_sourced 1
end

# if we haven't sourced the login config, do it
status is-login; and not set -q __fish_nixos_login_config_sourced
and begin
  source /etc/fish/loginShellInit.fish

  

  # and leave a note so we don't source this config section again from
  # this very shell (children will source the general config anew)
  set -g __fish_nixos_login_config_sourced 1
end

# if we haven't sourced the interactive config, do it
status is-interactive; and not set -q __fish_nixos_interactive_config_sourced
and begin
  
  alias l 'ls -alh'
alias ll 'ls -l'
alias ls 'ls --color=tty'

  source /etc/fish/interactiveShellInit.fish

  
  # This is a gross hack. Home-manager has options that aren't valid for the
# system-wide nixos configuration. As a result I have to source the plug-ins
# directly to get them to load. Further, this needs to happen as soon as
# possible in the interactive shell initialization because these will override
# _my_ overrides (below).

# grc
source ${pkgs.fishPlugins.grc}/share/fish/vendor_conf.d/grc.fish 
source ${pkgs.fishPlugins.grc}/share/fish/vendor_functions.d/grc.wrap.fish 

# bass
source ${pkgs.fishPlugins.bass}/share/fish/vendor_functions.d/bass.fish

# bobthefish
source ${pkgs.fishPlugins.bobthefish}/share/fish/vendor_functions.d/__bobthefish_glyphs.fish
source ${pkgs.fishPlugins.bobthefish}/share/fish/vendor_functions.d/fish_mode_prompt.fish
source ${pkgs.fishPlugins.bobthefish}/share/fish/vendor_functions.d/fish_right_prompt.fish
source ${pkgs.fishPlugins.bobthefish}/share/fish/vendor_functions.d/__bobthefish_colors.fish
source ${pkgs.fishPlugins.bobthefish}/share/fish/vendor_functions.d/fish_title.fish
source ${pkgs.fishPlugins.bobthefish}/share/fish/vendor_functions.d/__bobthefish_display_colors.fish
source ${pkgs.fishPlugins.bobthefish}/share/fish/vendor_functions.d/fish_prompt.fish
source ${pkgs.fishPlugins.bobthefish}/share/fish/vendor_functions.d/fish_greeting.fish
source ${pkgs.fishPlugins.bobthefish}/share/fish/vendor_functions.d/bobthefish_display_colors.fish


# foreign-env


# Handle root user shell needs.
if set -q DOAS_USER
    set -gx CURRENT_USER_HOME /home/$DOAS_USER
else
    set -gx CURRENT_USER_HOME $HOME
end

function boot_is_mounted --description "Checks if /boot and /boot/EFI are both mounted. If run with 'quiet' argument, simply returns a code."
    set quiet $argv[1]

    # Check if /boot is a mount point
    mountpoint -q /boot
    set boot_mounted $status

    # Check if /boot/EFI is a mount point
    mountpoint -q /boot/EFI
    set efi_mounted $status

    if test $boot_mounted -eq 0 -a $efi_mounted -eq 0
        if not test "$quiet" = "quiet"
            echo "/boot and /boot/EFI are mounted."
        end
        return 0
    else
        if not test "$quiet" = "quiet"
            echo "Boot volumes are not fully mounted."
        end
        return 1
    end
end

function boot_toggle_mounts --description="Toggle mounting of encrypted boot volumes"
    if boot_is_mounted "quiet"
        # If boot is mounted, unmount it
        unmount_boot
        # Check if unmount was successful
        if not boot_is_mounted "quiet"
            echo "Boot volumes have been unmounted successfully."
            return 0
        else
            echo "Failed to unmount boot volumes."
            return 1
        end
    else
        # If boot is not mounted, mount it
        mount_boot
        # Check if mount was successful
        if boot_is_mounted "quiet"
            echo "Boot volumes have been mounted successfully."
            return 0
        else
            echo "Failed to mount boot volumes."
            return 1
        end
    end
end

function certs_extract_dod --description='This process is a pain. Get the p7b, convert it to a PEM, split the pem, rename the individual files.'
    set src_file $argv[1]
    openssl pkcs7 -inform der -in $src_file -print_certs -out $src_file.pem
    mkdir certs
    cat $src_file.pem | awk 'split_after==1{n++;split_after=0} /-----END CERTIFICATE-----/ {split_after=1} {print > "cert" n ".pem"}'
    mv cert*.pem certs
    pushd certs
    for n in (ls cert*.pem)
        set new_name (openssl x509 -noout -subject -in $n | cut -d '=' -f 7 | xargs | string replace -a ' ' '_')
        mv $n $new_name.pem
    end
    popd
end

function display_fzf_files --description="Call fzf and preview file contents using bat."
    set preview_command "bat --theme=gruvbox-dark --color=always --style=header,grid --line-range :400 {}"
    fzf --ansi --preview $preview_command
end

function display_rg_piped_fzf --description="Pipe ripgrep output into fzf"
    rg . -n --glob "!.git/" | fzf
end

function do_startup --description="Call this from an interacive shell at startup to set the environment per interactive preferences."
    set -l container_count (count (docker ps -q))
    if test $container_count -gt 0
        docker stop (docker ps -q)
    end
    echo 2013266 | doas tee /proc/sys/vm/min_free_kbytes
    echo 1 | doas tee /proc/sys/vm/swappiness
    hostname_update
end

function export --description="Emulates the bash export command"
    if [ $argv ] 
        set var (echo $argv | cut -f1 -d=)
        set val (echo $argv | cut -f2 -d=)
        set -gx $var $val
    else
        echo 'export var=value'
    end
end

function fd_fzf --description="Pipe fd output to fzf"
    set fd_exists (which fd)
    if test -z "$fd_exists"
        return
    end
    if test (is_valid_dir $argv) = "true"
        set go_to (fd -t d . $argv | fzf)
        if test -z "$go_to"
            return
        else
            pushd $go_to
            return
        end
    else
        echo "Must provide a valid search path."
    end
end

function filename_get_random --description="Sometimes you need a random name for a file and UUIDs suck"
    pwgen --capitalize --numerals --ambiguous 16 1
end

function files_compare --description="Requires two file paths to compare."
    if test $argv[1] = "" -o $argv[2] = ""
        echo "Arguments required for two files. Exiting."
        return 1
    end
    if test (sha512sum $argv[1] | cut -d ' ' -f 1) = (sha512sum $argv[2] | cut -d ' ' -f 1)
        return 0
    else
        return 1
    end
end

function files_compare_verbose --description="Text output for files_compare"
    if files_compare $argv[1] $argv[2]
        echo "Hashes match."
        return 0
    else
        echo "Hashes do not match."
        return 1
    end
end

function fish_greeting --description="Displays the Fish logo and some other init stuff."
    set_color $fish_color_autosuggestion
    set_color normal
    neofetch
    fortune | \
        cowsay -n -f (set cows (ls ${pkgs.cowsay}/share/cowsay/cows); \
        set total_cows (count $cows); \
        set random_cow (random 1 $total_cows); \
        set my_cow $cows[$random_cow]; \
        echo -n $my_cow | 
            cut -d '.' -f 1) -W 79 | \
            lolcat --force | \
            cat
end

# This doesn't seem to work any longer with new setup. Consider removing.
function font_size --description="Adjusts the console font point size."
    if count $argv > /dev/null
        gsettings set org.gnome.desktop.interface monospace-font-name "UbuntuMono Nerd Font $argv"
    else
        gsettings get org.gnome.desktop.interface monospace-font-name
    end
end

function hash_get --description="Return a hash of the input string."
    echo -n $argv[1] | sha1sum | cut -d ' ' -f 1
end

function hostname_update --description="Update hostname to reflect current IP address."
    echo "This function needs updated for nixos."
    # This is a reasonably safe way to grab the currently configured network
    # device. This will currently only grab the current wifi adapter.
    #set m_if (ip -4 addr list | \
        #rg 'state\ UP' | \
        #rg -v 'br-' | \
        #cut -d ' ' -f 2 | \
        #string sub --end -1 | \
        #rg wl)

    # This is a reasonably safe way to grab the current IP address of the current network device.
    #set m_ip (ip -4 addr list | \
        #rg $m_if | \
        #rg 'dynamic' | \
        #string trim | \
        #cut -d ' ' -f 2 | \
        #rg -o '((1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])\.){3}(1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])')

    #set NEW_HOSTNAME precisionws.$m_ip.nip.io

    # nip.io creates resolvable hostnames by embedding their IP in the hostname
    # and then resolving the hostname to that IP address.
    # doas hostnamectl set-hostname precisionws.$m_ip.nip.io
    #echo $NEW_HOSTNAME | \
        #doas tee /etc/hostname /proc/sys/kernel/hostname >/dev/null
end

function journal_read --description 'Custom journal output format'
    journalctl -xf --no-pager --no-hostname -o json-seq --output-fields=MESSAGE,_CMDLINE,_PID | while read -l line
        # Preprocess the JSON entry to remove hidden characters
        set line_cleaned (echo $line | sed 's/[^[:print:]\t]//g')
        echo $line_cleaned | jq '.' > /dev/null 2>&1
        if test $status -eq 0
            # Process and format the valid JSON, and output it
            echo $line_cleaned | jq --unbuffered '
            def adjust_timestamp:
                ((2024 - 1900) * 31536000) +   # Adjustment for year difference
                (31 * 86400);                 # Adjustment for leap days

            def generate_timestamp:
                now | strftime("%Y-%m-%d %H:%M:%S");

            delpaths([
                ["_BOOT_ID"],
                ["__MONOTONIC_TIMESTAMP"],
                ["__CURSOR"],
                ["__REALTIME_TIMESTAMP"],
                ["__SEQNUM"],
                ["__SEQNUM_ID"]
            ])
            | if has("__REALTIME_TIMESTAMP") then
                .TIMESTAMP = (.["__REALTIME_TIMESTAMP"] | tonumber / 1000000 | todate)
              else
                . + { "TIMESTAMP": generate_timestamp }
              end
            | . as $entry
            | . |= with_entries(if .key == "_PID" then .key = "PID" | .value |= tonumber else . end)
            | . |= with_entries(if .key == "_CMDLINE" then .key = "CMDLINE" else . end)
            | to_entries | sort_by(.key) | from_entries
            '
        else
            echo "Invalid JSON: $line" >> error.log
        end
    end
end

function json_validate --description="Validate provided json against provided schema. E.g., 'validate_json file.json schema.json'. Can also handle json input from pipe via stdin."
    # jsonschema only operates via file input, which is inconvenient.
    if ! isatty stdin
        set -l tmp_file get_random_filename
        read > /tmp/$tmp_file; or exit -1
        jsonschema -F "{error.message}" -i /tmp/$tmp_file $argv[1]
        rm -f /tmp/$tmp_file
    else
        jsonschema -F "{error.message}" -i $argv[1] $argv[2]
    end
end

function layout_kitty --description="Create a layout file for kitty, based on the current layout, and reload kitty's config"
    # Define the output file
    set output_file $CURRENT_USER_HOME/.config/kitty/my_layout.conf

    # Start writing to the output file
    echo "# Kitty layout configuration" > $output_file
    echo "Creating layout configuration..."

    # Query Kitty for the current layout
    set layout (kitty @ ls | jq '.')

    # Extract the necessary details and write to the configuration file
    for window in (echo $layout | jq -c '.[]')
        echo "new_os_window" >> $output_file
        for tab in (echo $window | jq -c '.tabs[]')
            set tab_title (echo $tab | jq -r '.title')
            echo "new_tab $tab_title" >> $output_file
            echo "layout grid" >> $output_file

            # Collect all panes and their attributes
            set panes (echo $tab | jq -c '.windows[]')
            
            for pane in $panes
                set pane_id (echo $pane | jq -r '.id')
                set is_focused (echo $pane | jq -r '.is_focused')
                set columns (echo $pane | jq -r '.columns')
                set lines (echo $pane | jq -r '.lines')
                set cwd (echo $pane | jq -r '.cwd')
                set cmd (echo $pane | jq -r '.cmdline | join(" ")')

                if test $is_focused = "true"
                    echo "focus_window $pane_id" >> $output_file
                end

                echo "split --cwd $cwd --cmd \"$cmd\" --dimensions $lines,$columns" >> $output_file
            end
        end
    end

    echo "Layout configuration saved to $output_file"

    # Reload Kitty configuration using kitten icat (a hack to force reload)
    kitty +kitten icat --clear

    echo "Kitty configuration reloaded"
end

function lol --description="lolcat inside cowsay"
    echo $argv | \
        cowsay -n -f (set cows (ls /usr/share/cowsay/cows); \
        set total_cows (count $cows); \
        set random_cow (random 1 $total_cows); \
        set my_cow $cows[$random_cow]; \
        echo -n $my_cow | \
        cut -d '.' -f 1) -W 79 | \
        lolcat --force | \
        cat
end

function lol_fig --description="lolcat inside a figlet"
    echo $argv | figlet | lolcat -f | cat
end

function lh --description 'An approximation of "ls -alh", but uses eza, a replacement for ls, with some useful options as defaults.'
    eza --group --header --group-directories-first --long --icons --git --all --binary --dereference --links $argv
end

function lht --description="ls -alh, but show only files modified today"
    lh (find . -maxdepth 1 -type f -newermt (date +%Y-%m-%d) ! -newermt (date -d tomorrow +%Y-%m-%d))
end

function mac_generate --description="Generate valid MAC addresses, quickly. If an argument is provided, it must be one of: arista aruba cisco dell emc extreme_networks hp juniper riverbed vmware. The argument controls the vendor prefix portion of the generated MAC."
    # The following are vendor-owned MAC ranges, used for prefix generation:
    set arista \
    "00:1c:73" "28:99:3a" "40:01:07" "44:4c:a8"

    set aruba \
    "00:0b:86" "00:1a:1e" "00:24:6c" "04:bd:88" "18:64:72" "20:4c:03" "24:de:c6" "40:e3:d6" "6c:f3:7f" "70:3a:0e" \
    "84:d4:7e" "94:b4:0f" "9c:1c:12" "ac:a3:1e" "b4:5d:50" "d8:c7:c8" "f0:5c:19"

    set cisco \
    "00:00:0c" "00:01:42" "00:01:64" "00:01:96" "00:01:97" "00:01:c7" "00:01:c9" "00:02:17" "00:02:3d" "00:02:4a" \
    "00:02:4b" "00:02:7d" "00:02:7e" "00:02:b9" "00:02:ba" "00:02:fc" "00:02:fd" "00:03:31" "00:03:32" "00:03:6b" \
    "00:03:6c" "00:03:9f" "00:03:a0" "00:03:e3" "00:03:e4" "00:03:fd" "00:03:fe" "00:04:27" "00:04:28" "00:04:4d" \
    "00:04:4e" "00:04:6d" "00:04:6e" "00:04:9a" "00:04:9b" "00:04:c0" "00:04:c1" "00:04:dd" "00:04:de" "00:05:00" \
    "00:05:01" "00:05:31" "00:05:32" "00:05:5e" "00:05:5f" "00:05:73" "00:05:74" "00:05:9b" "00:05:dc" "00:05:dd" \
    "00:06:28" "00:06:2a" "00:06:52" "00:06:53" "00:06:7c" "00:06:c1" "00:06:d6" "00:06:d7" "00:06:f6" "00:07:0d" \
    "00:07:0e" "00:07:4f" "00:07:50" "00:07:7d" "00:07:84" "00:07:85" "00:07:b3" "00:07:b4" "00:07:eb" "00:07:ec" \
    "00:08:20" "00:08:21" "00:08:2f" "00:08:30" "00:08:31" "00:08:32" "00:08:7c" "00:08:7d" "00:08:a3" "00:08:a4" \
    "00:08:c2" "00:08:e2" "00:08:e3" "00:09:11" "00:09:12" "00:09:43" "00:09:44" "00:09:7b" "00:09:7c" "00:09:b6" \
    "00:09:b7" "00:09:e8" "00:09:e9" "00:0a:41" "00:0a:42" "00:0a:8a" "00:0a:8b" "00:0a:b7" "00:0a:b8" "00:0a:f3" \
    "00:0a:f4" "00:0b:45" "00:0b:46" "00:0b:5f" "00:0b:60" "00:0b:85" "00:0b:be" "00:0b:bf" "00:0b:fc" "00:0b:fd" \
    "00:0c:30" "00:0c:31" "00:0c:41" "00:0c:85" "00:0c:86" "00:0c:ce" "00:0c:cf" "00:0d:28" "00:0d:29" "00:0d:65" \
    "00:0d:66" "00:0d:bc" "00:0d:bd" "00:0d:ec" "00:0d:ed" "00:0e:08" "00:0e:38" "00:0e:39" "00:0e:83" "00:0e:84" \
    "00:0e:d6" "00:0e:d7" "00:0f:23" "00:0f:24" "00:0f:34" "00:0f:35" "00:0f:66" "00:0f:8f" "00:0f:90" "00:0f:f7" \
    "00:0f:f8" "00:10:07" "00:10:0b" "00:10:0d" "00:10:11" "00:10:14" "00:10:1f" "00:10:29" "00:10:2f" "00:10:54" \
    "00:10:79" "00:10:7b" "00:10:a6" "00:10:f6" "00:10:ff" "00:11:20" "00:11:21" "00:11:5c" "00:11:5d" "00:11:92" \
    "00:11:93" "00:11:bb" "00:11:bc" "00:12:00" "00:12:01" "00:12:17" "00:12:43" "00:12:44" "00:12:7f" "00:12:80" \
    "00:12:d9" "00:12:da" "00:13:10" "00:13:19" "00:13:1a" "00:13:5f" "00:13:60" "00:13:7f" "00:13:80" "00:13:c3" \
    "00:13:c4" "00:14:1b" "00:14:1c" "00:14:69" "00:14:6a" "00:14:a8" "00:14:a9" "00:14:bf" "00:14:f1" "00:14:f2" \
    "00:15:2b" "00:15:2c" "00:15:62" "00:15:63" "00:15:c6" "00:15:c7" "00:15:f9" "00:15:fa" "00:16:46" "00:16:47" \
    "00:16:9c" "00:16:9d" "00:16:b6" "00:16:c7" "00:16:c8" "00:17:0e" "00:17:0f" "00:17:3b" "00:17:59" "00:17:5a" \
    "00:17:94" "00:17:95" "00:17:df" "00:17:e0" "00:18:0a" "00:18:18" "00:18:19" "00:18:39" "00:18:68" "00:18:73" \
    "00:18:74" "00:18:b9" "00:18:ba" "00:18:f8" "00:19:06" "00:19:07" "00:19:2f" "00:19:30" "00:19:47" "00:19:55" \
    "00:19:56" "00:19:a9" "00:19:aa" "00:19:e7" "00:19:e8" "00:1a:2f" "00:1a:30" "00:1a:6c" "00:1a:6d" "00:1a:70" \
    "00:1a:a1" "00:1a:a2" "00:1a:e2" "00:1a:e3" "00:1b:0c" "00:1b:0d" "00:1b:2a" "00:1b:2b" "00:1b:53" "00:1b:54" \
    "00:1b:67" "00:1b:8f" "00:1b:90" "00:1b:d4" "00:1b:d5" "00:1b:d7" "00:1c:0e" "00:1c:0f" "00:1c:10" "00:1c:57" \
    "00:1c:58" "00:1c:b0" "00:1c:b1" "00:1c:f6" "00:1c:f9" "00:1d:45" "00:1d:46" "00:1d:70" "00:1d:71" "00:1d:7e" \
    "00:1d:a1" "00:1d:a2" "00:1d:e5" "00:1d:e6" "00:1e:13" "00:1e:14" "00:1e:49" "00:1e:4a" "00:1e:6b" "00:1e:79" \
    "00:1e:7a" "00:1e:bd" "00:1e:be" "00:1e:e5" "00:1e:f6" "00:1e:f7" "00:1f:26" "00:1f:27" "00:1f:6c" "00:1f:6d" \
    "00:1f:9d" "00:1f:9e" "00:1f:c9" "00:1f:ca" "00:21:1b" "00:21:1c" "00:21:29" "00:21:55" "00:21:56" "00:21:a0" \
    "00:21:a1" "00:21:be" "00:21:d7" "00:21:d8" "00:22:0c" "00:22:0d" "00:22:3a" "00:22:55" "00:22:56" "00:22:6b" \
    "00:22:90" "00:22:91" "00:22:bd" "00:22:be" "00:22:ce" "00:23:04" "00:23:05" "00:23:33" "00:23:34" "00:23:5d" \
    "00:23:5e" "00:23:69" "00:23:ab" "00:23:ac" "00:23:be" "00:23:ea" "00:23:eb" "00:24:13" "00:24:14" "00:24:50" \
    "00:24:51" "00:24:97" "00:24:98" "00:24:c3" "00:24:c4" "00:24:f7" "00:24:f9" "00:25:2e" "00:25:45" "00:25:46" \
    "00:25:83" "00:25:84" "00:25:9c" "00:25:b4" "00:25:b5" "00:26:0a" "00:26:0b" "00:26:51" "00:26:52" "00:26:98" \
    "00:26:99" "00:26:ca" "00:26:cb" "00:27:0c" "00:27:0d" "00:2a:10" "00:2a:6a" "00:2c:c8" "00:30:19" "00:30:24" \
    "00:30:40" "00:30:71" "00:30:78" "00:30:7b" "00:30:80" "00:30:85" "00:30:94" "00:30:96" "00:30:a3" "00:30:b6" \
    "00:30:f2" "00:35:1a" "00:38:df" "00:3a:7d" "00:3a:98" "00:3a:99" "00:3a:9a" "00:3a:9b" "00:3a:9c" "00:40:96" \
    "00:41:d2" "00:42:5a" "00:42:68" "00:50:0b" "00:50:0f" "00:50:14" "00:50:2a" "00:50:3e" "00:50:50" "00:50:53" \
    "00:50:54" "00:50:73" "00:50:80" "00:50:a2" "00:50:a7" "00:50:bd" "00:50:d1" "00:50:e2" "00:50:f0" "00:56:2b" \
    "00:57:d2" "00:59:dc" "00:5f:86" "00:60:09" "00:60:2f" "00:60:3e" "00:60:47" "00:60:5c" "00:60:70" "00:60:83" \
    "00:62:ec" "00:64:40" "00:6b:f1" "00:6c:bc" "00:76:86" "00:78:88" "00:81:c4" "00:87:31" "00:8a:96" "00:8e:73" \
    "00:90:0c" "00:90:21" "00:90:2b" "00:90:5f" "00:90:6d" "00:90:6f" "00:90:86" "00:90:92" "00:90:a6" "00:90:ab" \
    "00:90:b1" "00:90:bf" "00:90:d9" "00:90:f2" "00:9e:1e" "00:a0:c9" "00:a2:89" "00:a2:ee" "00:a6:ca" "00:a7:42" \
    "00:af:1f" "00:b0:4a" "00:b0:64" "00:b0:8e" "00:b0:c2" "00:b0:e1" "00:c0:1d" "00:c1:64" "00:c1:b1" "00:c8:8b" \
    "00:ca:e5" "00:cc:fc" "00:d0:06" "00:d0:58" "00:d0:63" "00:d0:79" "00:d0:90" "00:d0:97" "00:d0:ba" "00:d0:bb" \
    "00:d0:bc" "00:d0:c0" "00:d0:d3" "00:d0:e4" "00:d0:ff" "00:d7:8f" "00:da:55" "00:de:fb" "00:e0:14" "00:e0:1e" \
    "00:e0:34" "00:e0:4f" "00:e0:8f" "00:e0:a3" "00:e0:b0" "00:e0:f7" "00:e0:f9" "00:e0:fe" "00:e1:6d" "00:eb:d5" \
    "00:f2:8b" "00:f6:63" "00:f8:2c" "00:fe:c8" "02:07:01" "02:60:8c" "04:2a:e2" "04:62:73" "04:6c:9d" "04:c5:a4" \
    "04:da:d2" "04:fe:7f" "08:17:35" "08:1f:f3" "08:80:39" "08:96:ad" "08:cc:68" "08:cc:a7" "08:d0:9f" "0c:11:67" \
    "0c:27:24" "0c:68:03" "0c:75:bd" "0c:85:25" "0c:8d:db" "0c:d9:96" "0c:f5:a4" "10:05:ca" "10:5f:49" "10:8c:cf" \
    "10:bd:18" "10:ea:59" "10:f3:11" "18:33:9d" "18:55:0f" "18:59:33" "18:8b:45" "18:8b:9d" "18:9c:5d" "18:e7:28" \
    "18:ef:63" "1c:17:d3" "1c:1d:86" "1c:6a:7a" "1c:aa:07" "1c:de:a7" "1c:df:0f" "1c:e6:c7" "1c:e8:5d" "20:37:06" \
    "20:3a:07" "20:4c:9e" "20:aa:4b" "20:bb:c0" "24:01:c7" "24:37:4c" "24:76:7d" "24:b6:57" "24:e9:b3" "28:34:a2" \
    "28:52:61" "28:6f:7f" "28:93:fe" "28:94:0f" "28:c7:ce" "2c:0b:e9" "2c:31:24" "2c:33:11" "2c:36:f8" "2c:3e:cf" \
    "2c:3f:38" "2c:54:2d" "2c:5a:0f" "2c:86:d2" "2c:ab:a4" "2c:ab:eb" "2c:d0:2d" "30:37:a6" "30:e4:db" "30:f7:0d" \
    "34:62:88" "34:6f:90" "34:a8:4e" "34:bd:c8" "34:bd:fa" "34:db:fd" "38:1c:1a" "38:20:56" "38:5f:66" "38:c8:5c" \
    "38:ed:18" "3c:08:f6" "3c:0e:23" "3c:5e:c3" "3c:ce:73" "3c:df:1e" "40:55:39" "40:a6:e8" "40:f4:ec" "44:03:a7" \
    "44:2b:03" "44:58:29" "44:ad:d9" "44:d3:ca" "44:e0:8e" "44:e4:d9" "48:1d:70" "48:44:87" "48:f8:b3" "4c:00:82" \
    "4c:4e:35" "4c:83:de" "50:06:04" "50:06:ab" "50:17:ff" "50:1c:bf" "50:39:55" "50:3d:e5" "50:57:a8" "50:67:ae" \
    "50:87:89" "54:4a:00" "54:75:d0" "54:78:1a" "54:7c:69" "54:7f:ee" "54:a2:74" "54:d4:6f" "58:0a:20" "58:35:d9" \
    "58:6d:8f" "58:8d:09" "58:97:1e" "58:97:bd" "58:ac:78" "58:bc:27" "58:bf:ea" "58:f3:9c" "5c:50:15" "5c:83:8f" \
    "5c:a4:8a" "5c:fc:66" "60:2a:d0" "60:73:5c" "64:00:f1" "64:12:25" "64:16:8d" "64:9e:f3" "64:a0:e7" "64:ae:0c" \
    "64:d8:14" "64:d9:89" "64:e9:50" "64:f6:9d" "68:7f:74" "68:86:a7" "68:99:cd" "68:9c:e2" "68:bc:0c" "68:bd:ab" \
    "68:ee:96" "68:ef:bd" "6c:20:56" "6c:41:6a" "6c:50:4d" "6c:99:89" "6c:9c:ed" "6c:fa:89" "70:10:5c" "70:81:05" \
    "70:ca:9b" "70:d3:79" "70:db:98" "70:e4:22" "74:26:ac" "74:54:7d" "74:a0:2f" "74:a2:e6" "78:ba:f9" "78:da:6e" \
    "7c:0e:ce" "7c:69:f6" "7c:95:f3" "7c:ad:74" "7c:b2:1b" "80:e0:1d" "80:e8:6f" "84:3d:c6" "84:78:ac" "84:80:2d" \
    "84:8d:c7" "84:b2:61" "84:b5:17" "84:b8:02" "88:15:44" "88:1d:fc" "88:43:e1" "88:5a:92" "88:75:56" "88:90:8d" \
    "88:f0:31" "88:f0:77" "8c:60:4f" "8c:b6:4f" "94:d4:69" "98:fc:11" "9c:4e:20" "9c:57:ad" "9c:af:ca" "a0:3d:6f" \
    "a0:55:4f" "a0:cf:5b" "a0:e0:af" "a0:ec:f9" "a0:f8:49" "a4:0c:c3" "a4:18:75" "a4:4c:11" "a4:56:30" "a4:6c:2a" \
    "a4:93:4c" "a4:a2:4a" "a8:0c:0d" "a8:9d:21" "a8:b1:d4" "ac:7e:8a" "ac:a0:16" "ac:f2:c5" "b0:00:b4" "b0:7d:47" \
    "b0:aa:77" "b0:fa:eb" "b4:14:89" "b4:a4:e3" "b4:e9:b0" "b8:38:61" "b8:62:1f" "b8:be:bf" "bc:16:65" "bc:16:f5" \
    "bc:67:1c" "bc:c4:93" "bc:c8:10" "bc:d1:65" "bc:f1:f2" "c0:25:5c" "c0:62:6b" "c0:67:af" "c0:7b:bc" "c0:8c:60" \
    "c0:c1:c0" "c0:c6:87" "c4:0a:cb" "c4:14:3c" "c4:64:13" "c4:71:fe" "c4:72:95" "c4:7d:4f" "c4:b9:cd" "c8:00:84" \
    "c8:4c:75" "c8:9c:1d" "c8:b3:73" "c8:d7:19" "c8:f9:f9" "c8:fb:26" "cc:0d:ec" "cc:16:7e" "cc:46:d6" "cc:d5:39" \
    "cc:d8:c1" "cc:ef:48" "d0:57:4c" "d0:72:dc" "d0:a5:a6" "d0:c2:82" "d0:c7:89" "d0:d0:fd" "d4:2c:44" "d4:6d:50" \
    "d4:8c:b5" "d4:a0:2a" "d4:d7:48" "d8:24:bd" "d8:67:d9" "d8:b1:90" "dc:7b:94" "dc:a5:f4" "dc:ce:c1" "dc:eb:94" \
    "e0:0e:da" "e0:2f:6d" "e0:55:3d" "e0:5f:b9" "e0:89:9d" "e0:ac:f1" "e0:d1:73" "e4:48:c7" "e4:aa:5d" "e4:c7:22" \
    "e4:d3:f1" "e8:04:62" "e8:40:40" "e8:65:49" "e8:b7:48" "e8:ba:70" "e8:ed:f3" "ec:30:91" "ec:44:76" "ec:bd:1d" \
    "ec:c8:82" "ec:e1:a9" "f0:25:72" "f0:29:29" "f0:78:16" "f0:7f:06" "f0:9e:63" "f0:b2:e5" "f0:f7:55" "f4:0f:1b" \
    "f4:1f:c2" "f4:4b:2a" "f4:4e:05" "f4:5f:d4" "f4:7f:35" "f4:ac:c1" "f4:cf:e2" "f4:ea:67" "f8:0b:cb" "f8:4f:57" \
    "f8:66:f2" "f8:72:ea" "f8:a5:c5" "f8:c2:88" "fc:5b:39" "fc:99:47" "fc:fb:fb"
    set dell \
    "00:06:5b" "00:08:74" "00:0b:db" "00:0d:56" "00:0f:1f" "00:11:43" "00:12:3f" "00:13:72" "00:14:22" "00:15:c5" \
    "00:16:f0" "00:18:8b" "00:19:b9" "00:1a:a0" "00:1c:23" "00:1d:09" "00:1e:4f" "00:1e:c9" "00:21:70" "00:21:9b" \
    "00:22:19" "00:23:ae" "00:24:e8" "00:25:64" "00:26:b9" "00:c0:4f" "10:7d:1a" "10:98:36" "14:18:77" "14:9e:cf" \
    "14:b3:1f" "14:fe:b5" "18:03:73" "18:66:da" "18:a9:9b" "18:db:f2" "18:fb:7b" "1c:40:24" "20:47:47" "24:6e:96" \
    "24:b6:fd" "28:c8:25" "28:f1:0e" "34:17:eb" "34:e6:d7" "40:5c:fd" "44:a8:42" "48:4d:7e" "4c:76:25" "50:9a:4c" \
    "54:9f:35" "5c:26:0a" "5c:f9:dd" "64:00:6a" "74:86:7a" "74:e6:e2" "78:2b:cb" "78:45:c4" "80:18:44" "84:2b:2b" \
    "84:7b:eb" "84:8f:69" "90:b1:1c" "98:40:bb" "98:90:96" "a4:1f:72" "a4:ba:db" "b0:83:fe" "b4:e1:0f" "b8:2a:72" \
    "b8:ac:6f" "b8:ca:3a" "bc:30:5b" "c8:1f:66" "d0:43:1e" "d0:67:e5" "d4:81:d7" "d4:ae:52" "d4:be:d9" "e0:db:55" \
    "ec:f4:bb" "f0:1f:af" "f0:4d:a2" "f4:8e:38" "f8:b1:56" "f8:bc:12" "f8:ca:b8" "f8:db:88"
    set emc \
    "00:01:44" "00:12:48" "00:15:30" "00:1d:90" "00:21:88" "00:59:07" "00:60:48" "08:00:04" "24:37:ef"
    set extreme_networks \
    "00:01:30" "00:04:96" "00:e0:2b" "5c:0e:8b" "74:67:f7" "b4:c7:99" "b8:50:01" "d8:84:66" "fc:0a:81"
    set hp \
    "00:00:63" "00:00:c6" "00:01:e6" "00:01:e7" "00:02:a5" "00:04:ea" "00:06:0d" "00:08:02" "00:08:83" "00:0a:57" \
    "00:0b:cd" "00:0d:9d" "00:0e:7f" "00:0e:b3" "00:0f:20" "00:0f:61" "00:10:83" "00:10:e3" "00:11:0a" "00:11:85" \
    "00:12:79" "00:13:21" "00:14:38" "00:14:c2" "00:15:60" "00:16:35" "00:16:b9" "00:17:08" "00:17:a4" "00:18:71" \
    "00:18:fe" "00:19:bb" "00:1a:4b" "00:1b:3f" "00:1b:78" "00:1c:2e" "00:1c:c4" "00:1d:31" "00:1d:b3" "00:1e:0b" \
    "00:1f:28" "00:1f:29" "00:1f:fe" "00:21:5a" "00:21:f7" "00:22:64" "00:23:47" "00:23:7d" "00:24:81" "00:24:a8" \
    "00:25:61" "00:25:b3" "00:26:55" "00:26:f1" "00:30:6e" "00:30:c1" "00:40:17" "00:50:8b" "00:60:b0" "00:80:a0" \
    "00:9c:02" "00:a0:68" "00:fd:45" "08:00:09" "08:2e:5f" "10:00:90" "10:1f:74" "10:60:4b" "14:02:ec" "14:58:d0" \
    "18:a9:05" "1c:98:ec" "1c:c1:de" "24:be:05" "28:80:23" "28:92:4a" "2c:23:3a" "2c:27:d7" "2c:41:38" "2c:44:fd" \
    "2c:59:e5" "2c:76:8a" "30:8d:99" "30:e1:71" "34:64:a9" "34:fc:b9" "38:63:bb" "38:ea:a7" "3c:4a:92" "3c:52:82" \
    "3c:a8:2a" "3c:d9:2b" "40:a8:f0" "40:b0:34" "40:b9:3c" "44:1e:a1" "44:31:92" "44:48:c1" "48:0f:cf" "48:df:37" \
    "4c:39:09" "50:65:f3" "58:20:b1" "5c:8a:38" "5c:b9:01" "64:31:50" "64:51:06" "68:b5:99" "6c:3b:e5" "6c:c2:17" \
    "70:10:6f" "70:5a:0f" "74:46:a0" "78:48:59" "78:ac:c0" "78:e3:b5" "78:e7:d1" "80:c1:6e" "84:34:97" "88:51:fb" \
    "8c:dc:d4" "94:18:82" "94:57:a5" "98:4b:e1" "98:e7:f4" "9c:8e:99" "9c:b6:54" "9c:dc:71" "a0:1d:48" "a0:2b:b8" \
    "a0:48:1c" "a0:8c:fd" "a0:b3:cc" "a0:d3:c1" "a4:5d:36" "a8:bd:27" "ac:16:2d" "b0:5a:da" "b4:39:d6" "b4:99:ba" \
    "b4:b5:2f" "b8:af:67" "bc:ea:fa" "c0:91:34" "c4:34:6b" "c8:b5:ad" "c8:cb:b8" "c8:d3:ff" "cc:3e:5f" "d0:7e:28" \
    "d0:bf:9c" "d4:85:64" "d4:c9:ef" "d8:94:03" "d8:9d:67" "d8:d3:85" "dc:4a:3e" "e0:07:1b" "e4:11:5b" "e8:39:35" \
    "e8:f7:24" "ec:8e:b5" "ec:9a:74" "ec:b1:d7" "f0:62:81" "f0:92:1c" "f4:03:43" "f4:ce:46" "fc:15:b4" "fc:3f:db" \

    set juniper \
    "00:05:85" "00:10:db" "00:12:1e" "00:14:f6" "00:17:cb" "00:19:e2" "00:1b:c0" "00:1d:b5" "00:1f:12" "00:21:59" \
    "00:22:83" "00:23:9c" "00:24:dc" "00:26:88" "00:31:46" "00:90:69" "08:81:f4" "08:b2:58" "0c:05:35" "0c:86:10" \
    "10:0e:7e" "20:4e:71" "28:8a:1c" "28:a2:4b" "28:c0:da" "2c:21:31" "2c:21:72" "2c:6b:f5" "30:7c:5e" "30:b6:4f" \
    "3c:61:04" "3c:8a:b0" "3c:94:d5" "40:71:83" "40:a6:77" "40:b4:f0" "44:aa:50" "44:f4:77" "4c:96:14" "50:c5:8d" \
    "54:1e:56" "54:4b:8c" "54:e0:32" "5c:45:27" "5c:5e:ab" "64:64:9b" "64:87:88" "78:19:f7" "78:fe:3d" "80:71:1f" \
    "80:ac:ac" "84:18:88" "84:b5:9c" "84:c1:c1" "88:a2:5e" "88:e0:f3" "9c:cc:83" "a8:d0:e5" "ac:4b:c8" "b0:a8:6e" \
    "b0:c6:9a" "cc:e1:7f" "d4:04:ff" "dc:38:e1" "ec:13:db" "ec:3e:f7" "f0:1c:2d" "f4:a7:39" "f4:b5:2f" "f4:cc:55" \
    "f8:c0:01"

    set riverbed "00:0e:b6" "00:25:50" "6c:98:eb"
    set vmware "00:05:69" "00:0c:29" "00:1c:14" "00:50:56"

    set all_macs $arista $aruba $cisco $dell $emc $extreme_networks $hp $juniper $riverbed $vmware

    if test -n $argv[1]
        set vendor_names arista aruba cisco dell emc extreme_networks hp juniper riverbed vmware
        if contains $argv[1] $vendor_names
            switch $argv[1]
                case arista
                    set all_macs $arista
                case aruba
                    set all_macs $aruba
                case cisco
                    set all_macs $cisco
                case dell
                    set all_macs $dell
                case emc
                    set all_macs $emc
                case extreme_networks
                    set all_macs $extreme_networks
                case hp
                    set all_macs $hp
                case juniper
                    set all_macs $juniper
                case riverbed
                    set all_macs $riverbed
                case vmware
                    set all_macs $vmware
            end
        end
    end

    set hexchars "0123456789abcdef"

    # Vendors (Modified "top ten" in network hardware vendors listings)
    set prefix_count (count $all_macs)
    set random_mac (random 1 $prefix_count)
    set mac_prefix $all_macs[$random_mac]

    set suffix (for n in (seq 6); echo -n (string sub --start (random 1 16) --length 1 $hexchars); end | sed -e 's/\(..\)/:\1/g')

    # Example: 00:60:2f is the vendor prefix for Cisco. So, effectively, you're saying you are a piece of Cisco hardware if you use their suffix.
    echo $mac_prefix$suffix
end

function man --description="Get the page, man"
    /usr/bin/man $argv | bat --language man --style plain
end

function mount_boot --description "Mount the encrypted /boot and /boot/EFI partitions using Nix expressions"
    # Extract encrypted device path using Nix expressions
    set encrypted_device (nix eval --impure --raw --expr 'with import <nixpkgs/nixos> {}; config.boot.initrd.luks.devices."boot_crypt".device')
    if test -z "$encrypted_device"
        echo "Could not retrieve encrypted device path from NixOS configuration."
        return 1
    end

    # Resolve physical device if the device path is a symlink
    set encrypted_device_physical (readlink -f "$encrypted_device")
    if test -z "$encrypted_device_physical"
        echo "Could not resolve physical encrypted device path."
        return 1
    end

    # Open the encrypted boot partition
    echo "Opening encrypted boot partition..."
    sudo cryptsetup luksOpen "$encrypted_device_physical" boot_crypt
    if test $status -ne 0
        echo "Failed to open encrypted boot partition."
        return 1
    end

    # Mount /boot from the decrypted device
    echo "Mounting /boot..."
    sudo mount /dev/mapper/boot_crypt /boot
    if test $status -ne 0
        echo "Failed to mount /boot."
        return 1
    end

    # Extract device path for /boot/EFI using Nix expressions
    set efi_device (nix eval --impure --raw --expr 'with import <nixpkgs/nixos> {}; config.fileSystems."/boot/EFI".device')
    if test -z "$efi_device"
        echo "Could not retrieve /boot/EFI device path from NixOS configuration."
        return 1
    end

    # Resolve physical device if the device path is a symlink
    set efi_device_physical (readlink -f "$efi_device")
    if test -z "$efi_device_physical"
        echo "Could not resolve physical /boot/EFI device path."
        return 1
    end

    # Mount /boot/EFI
    echo "Mounting /boot/EFI..."
    sudo mount "$efi_device_physical" /boot/EFI
    if test $status -ne 0
        echo "Failed to mount /boot/EFI."
        return 1
    end

    echo "Boot partitions have been mounted successfully."
end

function unmount_boot
    # Unmount /boot/EFI
    if mountpoint -q /boot/EFI
        echo "Unmounting /boot/EFI..."
        sudo umount /boot/EFI
    else
        echo "/boot/EFI is not mounted."
    end

    # Unmount /boot
    if mountpoint -q /boot
        echo "Unmounting /boot..."
        sudo umount /boot
    else
        echo "/boot is not mounted."
    end

    # Close the encrypted boot partition
    if test -e /dev/mapper/boot_crypt
        echo "Closing encrypted boot partition..."
        sudo cryptsetup luksClose boot_crypt
    else
        echo "Encrypted boot partition is already closed."
    end
end

function myps --description="ps auww --ppid 2 -p2 --deselect"
    ps auww --ppid 2 -p2 --deselect
end

function nvim_goto_files --description="Open fzf to find a file, then open it in neovim"
    set nvim_exists (which nvim)
    if test -z "$nvim_exists"
        return
    end

    set selection (display_fzf_files)
    if test -z "$selection"
        return
    else
        nvim $selection
    end
end

function nvim_goto_line --description="ripgrep to find contents, search results using fzf, open selected result in neovim, on the appropriate line."
    set nvim_exists (which nvim)
    if test -z "$nvim_exists"
        return
    end

    set selection (display_rg_piped_fzf)
    if test -z "$selection"
        return
    else 
        set filename (echo $selection | awk -F ':' '{print $1}')
        set line (echo $selection | awk -F ':' '{print $2}')
        nvim +$line $filename
    end
end

function is_valid_dir --description="Checks if the argument passed is a valid directory path"
    if test (is_valid_argument $argv) = "true" -a (path_exists $argv) = "true" -a (is_a_directory $argv) = "true"
        echo "true"
    else
        echo "false"
    end
end

function is_valid_argument --description="Checks if it has been passed a valid argument"
    # Is there a valid argument?
    if test (count $argv) -gt 0
        echo "true"
    else
        echo "false"
    end
end

function path_exists --description="Checks if the path exists"
    # Does it exist?
    if test -e $argv[1]
        echo "true"
    else
        echo "false"
    end
end

function is_a_directory --description="Checks if the path is a directory"
    # Is it a directory?
    if test -d $argv[1]
        echo "true"
    else
        echo "false"
    end
end

function nixos_update --description="Update NixOS configuration with automatic boot mount handling"
    # Check if boot is mounted
    boot_is_mounted "quiet"
    set boot_was_mounted $status

    # If boot is not mounted, mount it
    if test $boot_was_mounted -ne 0
        echo "Boot volumes are not fully mounted. Mounting them now..."
        boot_toggle_mounts
        if test $status -ne 0
            echo "Failed to mount boot volumes. Aborting update."
            return 1
        end
    else
        echo "Boot volumes are already mounted."
    end

    # Run nixos-rebuild switch
    echo "Running nixos-rebuild switch..."
    sudo nixos-rebuild switch
    set rebuild_status $status

    # After rebuild, if boot was not mounted before, unmount it
    if test $boot_was_mounted -ne 0
        echo "Unmounting boot volumes..."
        boot_toggle_mounts
        if test $status -ne 0
            echo "Failed to unmount boot volumes."
            # Optionally, handle the error
        end
    else
        echo "Boot volumes remain mounted."
    end

    # Return the status of nixos-rebuild
    return $rebuild_status
end

function path_exists --description="Checks if the path exists"
    # Does it exist?
    if test -e $argv[1]
        echo "true"
    else
        echo "false"
    end
end

# Inspired by a Fish plug-in for Mac OS, this will work on Ubuntu, possibly others.
function ocd --description="Open the current terminal directory in your default file manager."
    echo "This function needs updated for nixos."
    #set sys_name (uname)
    #if test "$sys_name" = 'Darwin'
        #open $PWD
    #else if test "$sys_name" = 'Linux'
        #xdg-open $PWD 2>&1 > /dev/null
    #end
end

function pbcopy --description="Like, on Mac OS."
    echo "This function needs updated for nixos."
    #xclip -selection clipboard
end

function pbpaste --description="Like, on Mac OS."
    echo "This function needs updated for nixos."
    #xclip -selection clipboard -o
end

function port_find_open --description="Finds an open upper port"
    # lower and upper port bounds borrowed from Bash.
    while :
        set PULSE_PORT (shuf -i 32768-60999 -n 1)
        ss -lpn | rg -q ":$PULSE_PORT " || break
    end
    echo $PULSE_PORT
end

function prettyjson --description="Pretty print JSON output"
    python -m json.tool $argv[1]
end

function realtime_check --description="See what rtkit-daemon is up to."
    # We need the journal to just dump everything at once and not block.
    set SYSTEMD_PAGER cat

    # Get journal entries in a form we can use.
    # set json_journal (journalctl --no-hostname -xb -u rtkit-daemon --output=json)

    # Find journal entries related to rtkit performing a renice.
    # set downselect (echo $json_journal | jq -r 'select(.MESSAGE | contains("Successfully made thread")) | .MESSAGE')

    # Extract the PIDs of processes that are being reniced by rtkit.
    # set pids (echo $downselect | awk '{print $7}' | sort --sort=numeric | uniq)

    # Show the PIDs that are still alive. Tell us the name of the command and its nice level.
    # echo $pids | xargs -I{} ps -p {} -o cmd= -o pid= -o nice=
    journalctl --no-hostname -xb -u rtkit-daemon --output=json | \
        jq -r 'select(.MESSAGE | contains("Successfully made thread")) | .MESSAGE' | \
        awk '{print $7}' | \
        sort --sort=numeric | \
        uniq | \
        xargs -I{} ps -p {} -o cmd= -o pid= -o nice=
end

function root_is_immutable --description="Checks if root volume is mounted immutable. Can be run quiet or noisy."
    set quiet $argv[1]
    set mnt_state (mount | \
        rg nix-root\ on\ /\ type | \
        cut -d ' ' -f 6 | \
        cut -d ',' -f 1 | \
        string trim -c '(')
    if test $mnt_state = 'ro'
        if ! test "$quiet" = "quiet"
            echo "Fact."
        end
        return 0
    else
        if ! test "$quiet" = "quiet"
            echo "Root is mutable."
        end
        return 1
    end
end

function root_toggle_immutable --description="It's good to keep immutable root filesystem, unless it isn't."
    if root_is_immutable "quiet"
        doas mount -o remount rw /
    else
        doas mount -o remount ro /
    end
end

function showlog --description="journalctl with some niceties for realtime viewing"
    journalctl -xf --no-hostname
end

function signal_start --description="Start signal with appropriate options"
    signal-desktop-beta --no-sandbox >/dev/null 2>&1 &
end

# function sudo --description="doas is great but it fucks up the environment for root and is difficult to fix in other ways."
# env WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR XAUTHORITY=$XAUTHORITY $argv
# end

function tmp_is_immutable --description="Checks if tmp volume is mounted immutable. Can be run quiet or noisy."
    set quiet $argv[1]
    set mnt_state (mount | \
        rg ubun-tmp\ on\ /tmp\ type | \
        cut -d ' ' -f 6 | \
        cut -d ',' -f 1 | \
        string trim -c '(')
    if test $mnt_state = 'ro'
        if ! test "$quiet" = "quiet"
            echo "Fact."
        end
        return 0
    else
        if ! test "$quiet" = "quiet"
            echo "tmp is mutable."
        end
        return 1
    end
end

function tmp_toggle_immutable --description="It's good to keep immutable tmp filesystem, unless it isn't."
    if tmp_is_immutable "quiet"
        doas mount -o remount rw /tmp
    else
        doas mount -o remount ro /tmp
    end
end

function keyring_unlock --description="unlocks the gnome keyring from the shell"
    read -s -P "Password: " pass
    for m in (echo -n $pass | gnome-keyring-daemon --replace --unlock)
        export $m
    end
    set -e pass
end

function var_erase --description="Fish shell is missing a proper ability to delete a var from all scopes."
    set -el $argv[1]
    set -eg $argv[1]
    set -eU $argv[1]
end

function yaml_to_json --description="Converts YAML input to JSON output."
    python -c 'import sys, yaml, json; y=yaml.safe_load(sys.stdin.read()); print(json.dumps(y))' $argv[1] | read; or exit -1
end

# TODO: make sure this is still correct. This is used for updatedb, I seem to recall.
set -gx PRUNEPATHS /dev /proc /sys /run /media /backups /data /keys /lost+found /nix /sys /tmp

# For scripting code automation tasks.
set -gx CODE_ROOT $CURRENT_USER_HOME/Documents/projects/codes

# You'll want to install some nerd fonts, patched for powerline support of the theme.
# Recommend: 'UbuntuMono Nerd Font 13'
# gsettings set org.gnome.desktop.interface monospace-font-name 'UbuntuMono Nerd Font 13'
set -gx theme_nerd_fonts yes

# bobthefish is the theme of choice. This setting chooses a default color scheme.
#set -g theme_color_scheme gruvbox

# Gruvbox Color Palette
set -l foreground ebdbb2
set -l selection 282828 
set -l comment 928374 
set -l red fb4934
set -l orange fe8019
set -l yellow fabd2f
set -l green b8bb26
set -l cyan 8ec07c
set -l blue 83a598
set -l purple d3869b

# Syntax Highlighting Colors
set -g fish_color_normal $foreground
set -g fish_color_command $cyan
set -g fish_color_keyword $blue
set -g fish_color_quote $yellow
set -g fish_color_redirection $foreground
set -g fish_color_end $orange
set -g fish_color_error $red
set -g fish_color_param $purple
set -g fish_color_comment $comment
set -g fish_color_selection --background=$selection
set -g fish_color_search_match --background=$selection
set -g fish_color_operator $green
set -g fish_color_escape $blue
set -g fish_color_autosuggestion $comment

# Completion Pager Colors
set -g fish_pager_color_progress $comment
set -g fish_pager_color_prefix $cyan
set -g fish_pager_color_completion $foreground
set -g fish_pager_color_description $comment

set -gx theme_color_scheme gruvbox

set -gx theme_display_vi yes
set -gx theme_display_sudo_user yes
set -gx theme_show_exit_status yes
set -gx theme_display_jobs_verbose yes

# Vi key bindings
set -gx fish_key_bindings fish_vi_key_bindings

# The following plug-ins help us to:
#  - execute non-native scripts and capture their shell state for Fish
#  - Execute 'doas' efficiently, adding it when we may have forgot
#set -gx fish_plugins bass grc foreign-env bobthefish fzf fzf-fish 

# Tilix has some weirdness with Fish Shell, so in order to use their 'fix-up'
# script, we have to treat it with kid gloves.
#if test -n $TILIX_ID; or test -n $VTE_VERSION
    #bass source /etc/profile.d/vte.sh
#end

# Starship
source (starship init fish --print-full-init | psub)

# Atuin
atuin init fish | source

set -gx LS_COLORS 'rs=0:di=00;34:ln=00;36:mh=00:pi=40;33:so=00;35:do=00;35:bd=40;33;00:cd=40;33;00:or=40;31;00:mi=00:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=38;5;196:*.yaml=38;5;226:*.yml=38;5;226:*.json=38;5;226:*.csv=38;5;226:*.tar=38;5;207:*.tgz=38;5;207:*.arc=38;5;207:*.arj=38;5;207:*.taz=38;5;207:*.lha=38;5;207:*.lz4=38;5;207:*.lzh=38;5;207:*.lzma=38;5;207:*.tlz=38;5;207:*.txz=38;5;207:*.tzo=38;5;207:*.t7z=38;5;207:*.zip=38;5;207:*.z=38;5;207:*.dz=38;5;207:*.gz=38;5;207:*.lrz=38;5;207:*.lz=38;5;207:*.lzo=38;5;207:*.xz=38;5;207:*.zst=38;5;207:*.tzst=38;5;207:*.bz2=38;5;207:*.bz=38;5;207:*.tbz=38;5;207:*.tbz2=38;5;207:*.tz=38;5;207:*.deb=38;5;207:*.rpm=38;5;207:*.jar=38;5;207:*.war=38;5;207:*.ear=38;5;207:*.sar=38;5;207:*.rar=38;5;207:*.alz=38;5;207:*.ace=38;5;207:*.zoo=38;5;207:*.cpio=38;5;207:*.7z=38;5;207:*.rz=38;5;207:*.cab=38;5;207:*.wim=38;5;207:*.swm=38;5;207:*.dwm=38;5;207:*.esd=38;5;207:*.jpg=00;35:*.jpeg=00;35:*.mjpg=00;35:*.mjpeg=00;35:*.gif=00;35:*.bmp=00;35:*.pbm=00;35:*.pgm=00;35:*.ppm=00;35:*.tga=00;35:*.xbm=00;35:*.xpm=00;35:*.tif=00;35:*.tiff=00;35:*.png=00;35:*.svg=00;35:*.svgz=00;35:*.mng=00;35:*.pcx=00;35:*.mov=00;35:*.mpg=00;35:*.mpeg=00;35:*.m2v=00;35:*.mkv=00;35:*.webm=00;35:*.webp=00;35:*.ogm=00;35:*.mp4=00;35:*.m4v=00;35:*.mp4v=00;35:*.vob=00;35:*.qt=00;35:*.nuv=00;35:*.wmv=00;35:*.asf=00;35:*.rm=00;35:*.rmvb=00;35:*.flc=00;35:*.avi=00;35:*.fli=00;35:*.flv=00;35:*.gl=00;35:*.dl=00;35:*.xcf=00;35:*.xwd=00;35:*.yuv=00;35:*.cgm=00;35:*.emf=00;35:*.ogv=00;35:*.ogx=00;35:*.aac=00;36:*.au=00;36:*.flac=00;36:*.m4a=00;36:*.mid=00;36:*.midi=00;36:*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:*.oga=00;36:*.opus=00;36:*.spx=00;36:*.xspf=00;36:'

set -gx EZA_COLORS '*.tar=38;5;203:*.tgz=38;5;203:*.arc=38;5;203:*.arj=38;5;203:*.taz=38;5;203:*.lha=38;5;203:*.lz4=38;5;203:*.lzh=38;5;203:*.lzma=38;5;203:*.tlz=38;5;203:*.txz=38;5;203:*.tzo=38;5;203:*.t7z=38;5;203:*.zip=38;5;203:*.z=38;5;203:*.dz=38;5;203:*.gz=38;5;203:*.lrz=38;5;203:*.lz=38;5;203:*.lzo=38;5;203:*.xz=38;5;203:*.zst=38;5;203:*.tzst=38;5;203:*.bz2=38;5;203:*.bz=38;5;203:*.tbz=38;5;203:*.tbz2=38;5;203:*.tz=38;5;203:*.deb=38;5;203:*.rpm=38;5;203:*.jar=38;5;203:*.war=38;5;203:*.ear=38;5;203:*.sar=38;5;203:*.rar=38;5;203:*.alz=38;5;203:*.ace=38;5;203:*.zoo=38;5;203:*.cpio=38;5;203:*.7z=38;5;203:*.rz=38;5;203:*.cab=38;5;203:*.wim=38;5;203:*.swm=38;5;203:*.dwm=38;5;203:*.esd=38;5;203:*.doc=38;5;109:*.docx=38;5;109:*.pdf=38;5;109:*.txt=38;5;109:*.md=38;5;109:*.rtf=38;5;109:*.odt=38;5;109:*.yaml=38;5;172:*.yml=38;5;172:*.json=38;5;172:*.toml=38;5;172:*.conf=38;5;172:*.config=38;5;172:*.ini=38;5;172:*.env=38;5;172:*.jpg=38;5;132:*.jpeg=38;5;132:*.png=38;5;132:*.gif=38;5;132:*.bmp=38;5;132:*.tiff=38;5;132:*.svg=38;5;132:*.mp3=38;5;72:*.wav=38;5;72:*.aac=38;5;72:*.flac=38;5;72:*.ogg=38;5;72:*.m4a=38;5;72:*.mp4=38;5;72:*.avi=38;5;72:*.mov=38;5;72:*.mkv=38;5;72:*.flv=38;5;72:*.wmv=38;5;72:*.c=38;5;142:*.cpp=38;5;142:*.py=38;5;142:*.java=38;5;142:*.js=38;5;142:*.ts=38;5;142:*.go=38;5;142:*.rs=38;5;142:*.php=38;5;142:*.html=38;5;142:*.css=38;5;142::*.nix=38;5;142:*.rs=38;5;142di=38;5;109:ur=38;5;223:uw=38;5;203:ux=38;5;142:ue=38;5;142:gr=38;5;223:gw=38;5;203:gx=38;5;142:tr=38;5;223:tw=38;5;203:tx=38;5;142:su=38;5;208:sf=38;5;208:xa=38;5;108:nb=38;5;244:nk=38;5;108:nm=38;5;172:ng=38;5;208:nt=38;5;203:ub=38;5;244:uk=38;5;108:um=38;5;172:ug=38;5;208:ut=38;5;203:lc=38;5;208:lm=38;5;208:uu=38;5;223:gu=38;5;223:un=38;5;223:gn=38;5;223:da=38;5;109:ga=38;5;108:gm=38;5;109:gd=38;5;203:gv=38;5;142:gt=38;5;108:gi=38;5;244:gc=38;5;203:Gm=38;5;108:Go=38;5;172:Gc=38;5;142:Gd=38;5;203:xx=38;5;237'

set -gx BROWSER /etc/profiles/per-user/djshepard/bin/firefox

# Set these to get Wayland working...
############################################################
#set -gx __EGL_VENDOR_LIBRARY_FILENAMES /usr/share/glvnd/egl_vendor.d/10_nvidia.json /usr/share/glvnd/egl_vendor.d/50_mesa.json
#set -gx GBM_BACKEND nvidia-drm
#set -gx __GLX_VENDOR_LIBRARY_NAME nvidia
#set -gx _JAVA_AWT_WM_NONREPARENTING 1
#set -gx MOZ_ENABLE_WAYLAND 1
#set -gx QT_QPA_PLATFORMTHEME "wayland"
#set -gx QT_QPA_PLATFORM "wayland"
#set -gx SDL_VIDEODRIVER wayland
# set -gx WLR_DRM_NO_ATOMIC 1
# set -gx WLR_NO_HARDWARE_CURSORS 1
#set -gx XDG_CONFIG_HOME $CURRENT_USER_HOME/.config
#set -gx XDG_SESSION_TYPE wayland
# 
#set -gx ENABLE_VKBASALT 1
#set -gx LIBVA_DRIVER_NAME nvidia

# set -gx __NV_PRIME_RENDER_OFFLOAD 1
############################################################

# Set variables for Java
#set -gx JAVA_HOME /usr/lib/jvm/jdk-17
#set -gx MOZILLA_HOME $CURRENT_USER_HOME/.mozilla

# Pyenv
#set -gx PYENV_ROOT $CURRENT_USER_HOME/.pyenv

#set -gx PATH $PYENV_ROOT/bin $PATH
#$PYENV_ROOT/bin/pyenv init - | source
#status --is-interactive; and $PYENV_ROOT/bin/pyenv virtualenv-init - | source


# For Lorri projects.
#direnv hook fish | source

# For Home Manager
# TODO: Figure out why setting this hangs the shell.
#babelfish $CURRENT_USER_HOME/.nix-profile/etc/profile.d/hm-session-vars.sh | source
# NodeJS version manager configuration
set -xg NVM_DIR "$HOME/.config/nvm"
# fenv source $NVM_DIR/nvm.sh
#bass source $NVM_DIR/nvm.sh
# set -xg PATH "/home/djshepard/.config/nvm/versions/node/v21.7.3/bin" $PATH

#set -xg CNI_PATH "$CURRENT_USER_HOME/go/bin"

#set -xg GOENV_ROOT $CURRENT_USER_HOME/.goenv
#set -xg PATH $PATH $GOENV_ROOT/bin

#status --is-interactive; and source (goenv init -|psub)

#set -xg PATH $PATH $GOROOT/bin
#set -xg PATH $PATH $GOPATH/bin

#gsettings set org.gnome.mutter experimental-features "['dma-buf-screen-sharing']"

# Wasmer
#set -xg WASMER_DIR "$CURRENT_USER_HOME/.wasmer"
#if test -e $WASMER_DIR/wasmer.sh
#fenv source $WASMER_DIR/wasmer.sh
#end

if set -q KITTY_INSTALLATION_DIR
    set --global KITTY_SHELL_INTEGRATION enabled no-sudo
    source "$KITTY_INSTALLATION_DIR/shell-integration/fish/vendor_conf.d/kitty-shell-integration.fish"
    set --prepend fish_complete_path "$KITTY_INSTALLATION_DIR/shell-integration/fish/vendor_completions.d"
end

# This version uses 'fd', instead of find.
set -xg FZF_CTRL_T_COMMAND "fd --type file --hidden 2>/dev/null | sed 's#^\./##'"

# This version doesn't ignore files in .gitignore
#set -xg FZF_CTRL_T_COMMAND "fd --type file --hidden --no-ignore-vcs 2>/dev/null | sed 's#^\./##'"

set -xg BAT_THEME gruvbox-dark

# TODO: Experiment with this:
#set -xg BAT_PAGER "less -RF"

set -xg MANPAGER "sh -c 'col -bx | bat --language man --style plain'"

set -xg FZF_DEFAULT_OPTS '--prompt="🔭 " --height 80% --layout=reverse --border'

set -xg FZF_DEFAULT_COMMAND 'rg --files --no-ignore --hidden --follow --glob "!.git/"'

set -xg BAT_THEME gruvbox-dark

set -xg EDITOR ${pkgs.neovim}/bin/nvim

#set -xg VIM $CURRENT_USER_HOME/.config/nvim

set -xg TERM xterm-kitty
#set -xg TERM xterm-256color

set -xg SHELL ${pkgs.fish}/bin/fish

set -xg NIXOS_OZONE_WL 1

# Aliases:
function nvimf
    nvim_goto_files $argv
end

function nviml
    nvim_goto_line $argv
end

function fdfz
    fd_fzf $argv
end

function rgk
    rg --hyperlink-format=kitty $argv
end

function nvrun
    env __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia $argv
end
# add completions generated by NixOS to $fish_complete_path
begin
  # joins with null byte to accommodate all characters in paths, then respectively gets all paths before (exclusive) / after (inclusive) the first one including "generated_completions",
  # splits by null byte, and then removes all empty lines produced by using 'string'
  set -l prev (string join0 $fish_complete_path | string match --regex "^.*?(?=\x00[^\x00]*generated_completions.*)" | string split0 | string match -er ".")
  set -l post (string join0 $fish_complete_path | string match --regex "[^\x00]*generated_completions.*" | string split0 | string match -er ".")
  set fish_complete_path $prev "/etc/fish/generated_completions" $post
end
# prevent fish from generating completions on first run
if not test -d $__fish_user_data_dir/generated_completions
  /nix/store/sf6y4arqcm100rnnl3dhpg732i774zp6-coreutils-9.5/bin/mkdir $__fish_user_data_dir/generated_completions
end


  # and leave a note so we don't source this config section again from
  # this very shell (children will source the general config anew,
  # allowing configuration changes in, e.g, aliases, to propagate)
  set -g __fish_nixos_interactive_config_sourced 1
end
  '';
in
myFishConfig