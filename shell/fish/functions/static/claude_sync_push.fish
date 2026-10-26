function claude_sync_push --description "Copy Claude Code's sessions and memory (~/.claude/projects, settings.json) to the sync host, for claude_sync_pull on another machine. Extra arguments go to rsync (-n: show what would be copied)."
    # Where they go: an ssh host and a directory in its home. gitea is the host in ~/.ssh/config.
    set -l remote (set -q CLAUDE_SYNC_REMOTE; and echo $CLAUDE_SYNC_REMOTE; or echo "gitea:claude-sync")
    set -l host (string split -m1 ":" $remote)[1]
    set -l dir (string split -m1 ":" $remote)[2]
    # The gitea host forwards a port; a sync needs none.
    set -l ssh_cmd "ssh -o ClearAllForwardings=yes"

    if not test -d "$HOME/.claude/projects"
        echo "⚠️  No ~/.claude/projects here: nothing to push"
        return 1
    end

    # The transcripts hold whatever a session printed, secrets included: the directory is the owner's alone.
    eval $ssh_cmd $host "'mkdir -p -m 700 $dir && chmod 700 $dir'"; or return 1

    # Never .credentials.json (the Claude login), shell snapshots or session environments (environment variables).
    # --update: a file newer on the other side (a session continued there) is left as it is.
    rsync -a --update --chmod=Du=rwx,Dgo=,Fu=rw,Fgo= -e "$ssh_cmd" $argv \
        "$HOME/.claude/projects" "$HOME/.claude/settings.json" "$remote/"
    or return 1

    echo "✅ Claude sessions and memory pushed to $remote"
end
