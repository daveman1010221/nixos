function flake_restore --argument-names backup_dir
    if not test -d "$backup_dir"
        echo "❌ Backup directory not found: $backup_dir"
        return 1
    end
    
    if not test -f "$backup_dir/flake.lock"
        echo "❌ No flake.lock found in: $backup_dir"
        return 1
    end
    
    cp "$backup_dir/flake.lock" ./flake.lock
    echo "✅ Restored flake.lock from $backup_dir"
    
    if test -f "$backup_dir/archive.json"
        set -l store_path (jq -r '.path' < "$backup_dir/archive.json")
        echo "ℹ️  Archived store path (read-only): $store_path"
    else
        echo "⚠️  No archive.json found in backup"
    end
end
