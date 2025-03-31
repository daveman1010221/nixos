function kind_stop
    set mount_point /mnt/kind-kubelet

    # Check for and stop dev-control-plane if running
    if docker ps --format '{{.Names}}' | grep -q '^dev-control-plane$'
        echo "Stopping kind container..."
        docker stop dev-control-plane
    else if docker ps -a --format '{{.Names}}' | grep -q '^dev-control-plane$'
        echo "Container is already stopped."
    else
        echo "kind has not been started (no container found)."
    end

    # Unmount the loop device if it's mounted
    if mount | grep -q $mount_point
        echo "Unmounting $mount_point..."
        sudo umount $mount_point
    else
        echo "No loopback mount found for kind."
    end
end
