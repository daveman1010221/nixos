{ cowsayPath, ... }:

''
function fish_greeting --description="Displays the Fish logo and some other init stuff."
    set_color $fish_color_autosuggestion
    set_color normal
    neofetch
    fortune | \
        cowsay -n -f (set cows (ls ${cowsayPath}/share/cowsay/cows); \
        set total_cows (count $cows); \
        set random_cow (random 1 $total_cows); \
        set my_cow $cows[$random_cow]; \
        echo -n $my_cow | 
            cut -d '.' -f 1) -W 79 | \
            lolcat
end
''
