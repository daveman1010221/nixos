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
