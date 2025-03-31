function kind_start
    set img_path ~/kubelet.img
    set mount_point /mnt/kind-kubelet

    # Ensure the image exists
    if not test -e $img_path
        echo "Creating $img_path..."
        sudo fallocate -l 80G $img_path
        sudo mkfs.ext4 $img_path
    end

    # Ensure the mount point exists and is mounted
    if not mount | grep -q $mount_point
        echo "Mounting $img_path to $mount_point..."
        sudo mkdir -p $mount_point
        sudo mount -o loop $img_path $mount_point
    end

    # Check if dev-control-plane container exists
    if docker ps -a --format '{{.Names}}' | grep -q '^dev-control-plane$'
        echo "Starting existing kind container..."
        docker start dev-control-plane
    else
        echo "Creating new kind cluster..."
        kind create cluster
    end
end
