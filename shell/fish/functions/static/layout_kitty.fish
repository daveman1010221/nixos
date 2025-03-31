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
