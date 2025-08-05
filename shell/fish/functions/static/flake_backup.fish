function flake_backup
    set -l backup_dir "$HOME/nix-flake-backups"
    set -l timestamp (date "+%Y%m%d%H%M%S")
    set -l backup_path "$backup_dir/$timestamp"
    
    mkdir -p "$backup_path"
    
    if test -f flake.lock
        cp flake.lock "$backup_path/flake.lock"
        echo "🔐 Copied flake.lock to $backup_path/flake.lock"
    else
        echo "⚠️  No flake.lock found in current directory"
    end
    
    nix flake archive . --json > "$backup_path/archive.json"
    echo "📦 Saved flake archive metadata to $backup_path/archive.json"
    
    set -l store_path (jq -r '.path' < "$backup_path/archive.json")
    echo "📍 Archived store path: $store_path"
    
    echo "✅ Backup complete: $backup_path"
end
