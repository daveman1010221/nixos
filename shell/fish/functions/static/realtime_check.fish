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
