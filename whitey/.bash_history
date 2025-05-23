glmark2-drm
exit
glmark2
glmark2-drm
glmark2-egl
glmark2-es2
glmark2-es2-drm
glmark2-es2-gbm 
glmark2-es2-wayland 
glmark2-gbm
glmark2-wayland 
exit
geekbench6
geekbench_x86_64 
exit
bonnie++ 
swapon --show
bonnie++ 
exit
furmark 
furmark --demo furmark-gl --p1080
furmark --demo furmark-gl --p1080 --msaa 4
furmark --help
exit
lh
ll
exit
kitty
exit
glmark2-wayland 
exit
tree /sys/class/wmi_bus/
tree -R /sys/class/wmi_bus/
tree -r /sys/class/wmi_bus/
man tree
tree -l /sys/class/wmi_bus/
find /sys/class/wmi_bus/ -name modalias | xargs -I{} grep -H . {}
find /sys/class/wmi_bus/ -type f -name modalias
sudo modprobe it87
sudo modprobe ec_sys
ll /sys/class/hwmon/
lspci -v
exit
lspci -v
sudo dmesg | grep -i ec
exit
fio --name=seqread     --filename=/mnt/testfile     --rw=read     --bs=512k     --iodepth=64     --numjobs=4     --size=8G     --direct=1     --runtime=30     --time_based
sudo fio --name=seqread --filename=./testfile --rw=read --bs=512k --iodepth=64 --numjobs=4 --size=8G --direct=1 --runtime=30 --time_based
sudo fio --name=seqread     --filename=./testfile     --rw=read     --bs=512k     --iodepth=64     --numjobs=4     --size=8G     --direct=1     --runtime=30     --ioengine=io_uring     --time_based
sudo fio --name=rawread   --filename=/dev/nvme0n1   --rw=read   --bs=512k   --iodepth=64   --numjobs=4   --direct=1   --size=8G   --offset=64G   --ioengine=io_uring   --runtime=30   --time_based
lh testfile 
ls -alh testfile 
nvim testfile 
sudo dd if=/dev/nvme0n1 of=/dev/null bs=1M status=progress
sudo lspci -vv -s $(lspci | grep -i nvme | awk '{print $1}')
exit
sudo lspci -vv -s $(lspci | grep -i nvme | awk '{print $1}')
sudo lspci -vv | grep -A20 -i nvme
sudo fio --name=rawread-max   --filename=/dev/nvme0n1   --rw=read   --bs=1024k   --iodepth=128   --numjobs=8   --offset=0   --size=16G   --direct=1   --ioengine=io_uring   --time_based   --runtime=30   --group_reporting
exit
sudo fio --name=rawread-max   --filename=/dev/nvme0n1   --rw=read   --bs=1024k   --iodepth=128   --numjobs=8   --offset=0   --size=16G   --direct=1   --ioengine=io_uring   --time_based   --runtime=30   --group_reporting
exit
openssl enc -aes-256-ctr -pass pass:random -nosalt   </dev/zero > ./testfile bs=1M count=16384 status=progress
sudo rm testfile 
openssl enc -aes-256-ctr -pass pass:random -nosalt   </dev/zero > ./testfile bs=1M count=16384 status=progress
openssl enc -aes-256-ctr -pass pass:random -nosalt </dev/zero | dd of=./testfile bs=1M count=16384 status=progress
ll testfile 
ls -alh testfile 
openssl enc -aes-256-ctr -pass pass:random -nosalt </dev/zero | dd of=./testfile bs=1M count=16384 iflag=fullblock status=progress
ls -alh testfile 
sudo fio --name=f2fs-incomp   --filename=./testfile   --rw=read   --bs=512k   --iodepth=64   --numjobs=4   --direct=1   --ioengine=io_uring   --runtime=30   --time_based   --group_reporting
exit
sudo fio --name=f2fs-incomp   --filename=./testfile   --rw=read   --bs=512k   --iodepth=64   --numjobs=4   --direct=1   --ioengine=io_uring   --runtime=30   --time_based   --group_reporting
dd if=/dev/zero of=./testfile-compressible bs=1M count=16384 status=progress
sudo fio --name=f2fs-comp   --filename=./testfile-compressible   --rw=read   --bs=512k   --iodepth=64   --numjobs=4   --direct=1   --ioengine=io_uring   --runtime=30   --time_based   --group_reporting
pwd
mount | grep home
lspci -tv
exit
lspci -tv
exit
compilebench --help
compilebench
exit
compilebench
compilebench .
exit
clear
git clone https://github.com/osandov/compilebench
exit
geekbench
geekbench6
exit
sudo fio --name=f2fs-comp   --filename=./testfile-compressible   --rw=read   --bs=512k   --iodepth=64   --numjobs=4   --direct=1   --ioengine=io_uring   --runtime=30   --time_based   --group_reporting
exit
fish
exit
geekbench6
exit
openrgb 
sudo -E openrgb 
exit
lspci -vvv | grep -i rgb
lsusb -vvv | grep -i rgb
exit
lsusb -vvv | grep -i rgb
exit
fish
exit
superiotool --help
sudo superiotool
sudo superiotool --dump
lspci -vvv | grep -i rgb
sudo superiotool --list-supported
exit
fish
exit
cd /etc/nixos/
nvim configuration.nix 
sudo nvim configuration.nix 
sudo nvim configuration.nix 
sudo nixos-rebuild switch
sudo nvim configuration.nix 
sudo nixos-rebuild switch
exit
sudo fio --name=f2fs-comp   --filename=./testfile-compressible   --rw=read   --bs=512k   --iodepth=64   --numjobs=4   --direct=1   --ioengine=io_uring   --runtime=30   --time_based   --group_reporting
sudo fio --name=f2fs-comp   --filename=./testfile-compressible   --rw=read   --bs=512k   --iodepth=64   --numjobs=4   --direct=1   --ioengine=io_uring   --runtime=30   --time_based   --group_reporting
sudo fio --name=f2fs-comp   --filename=./testfile-compressible   --rw=read   --bs=512k   --iodepth=64   --numjobs=4   --direct=1   --ioengine=io_uring   --runtime=30   --time_based   --group_reporting
exit
fish
exit
fish
exit
kitty
geekbench6
exit
