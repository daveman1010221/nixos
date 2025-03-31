function lol_fig --description="lolcat inside a figlet"
    echo $argv | figlet | lolcat -f | cat
end
