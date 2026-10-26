function claude_sync_pull --description "Bring Claude Code's sessions and memory from the sync host (claude_sync_push on another machine) into ~/.claude. Extra arguments go to rsync (-n: show what would be copied)."
    set -l remote (set -q CLAUDE_SYNC_REMOTE; and echo $CLAUDE_SYNC_REMOTE; or echo "gitea:claude-sync")
    set -l ssh_cmd "ssh -o ClearAllForwardings=yes"

    mkdir -p "$HOME/.claude"
    chmod 700 "$HOME/.claude"

    # Safe beside the sessions already here: each session is its own file (named by its id), nothing here is deleted,
    # and --update leaves a file that is newer here as it is. What is shared, a project's memory (MEMORY.md and its
    # notes), is replaced by a newer copy whole, not merged: what it replaces is kept as <file>.before-pull.
    # Don't pull while a session runs in one of these projects: its transcript is being written.
    rsync -a --update --backup --suffix=.before-pull --chmod=Du=rwx,Dgo=,Fu=rw,Fgo= -e "$ssh_cmd" $argv \
        "$remote/projects" "$HOME/.claude/"
    or return 1
    # This machine's settings stay its own: settings.json comes over only when there is none.
    rsync -a --ignore-existing --chmod=Fu=rw,Fgo= -e "$ssh_cmd" $argv "$remote/settings.json" "$HOME/.claude/settings.json"
    or return 1

    # A session is kept under its directory's path (~/Documents/projects/Polar is -home-<user>-Documents-projects-Polar):
    # `claude --resume` in the same directory here finds it.
    echo "✅ Claude sessions and memory pulled from $remote: claude --resume in the project's directory"
end
