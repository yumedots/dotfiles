#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUNS=${DOTFILES_VM_RUNS:-$ROOT/vm/runs}
VIRTIOFSD=${VIRTIOFSD:-/usr/lib/virtiofsd}

action=${1:-print}
shift || true
name=${1:-}
mode=${2:-headless}
cores=${VM_CORES:-4}
mem=${VM_MEM:-4G}
cid=${VM_CID:-3}
dir=$RUNS/$name
disk=$dir/disk.qcow2

if [ -z "$name" ] || [ ! -f "$disk" ]; then
	echo "usage: vm/qemu.sh print|run <name> [headless|view] (create the overlay first)" >&2
	exit 2
fi

args=(
	-name "yudae-$name"
	-machine "q35,accel=kvm"
	-cpu host
	-smp "$cores"
	-m "$mem"
	-object "memory-backend-memfd,id=mem,size=$mem,share=on"
	-numa "node,memdev=mem"
	-drive "file=$disk,if=virtio,format=qcow2,cache=none,aio=io_uring"
	-device "virtio-gpu-gl-pci,max_outputs=1"
	-device "virtio-balloon-pci,free-page-reporting=on"
	-device "vhost-vsock-pci,guest-cid=$cid"
	-chardev "socket,id=vfs0,path=$dir/virtiofsd.sock"
	-device "vhost-user-fs-pci,chardev=vfs0,tag=dotfiles"
	-vga none
	-device "virtio-rng-pci"
	-netdev "user,id=net0"
	-device "virtio-net-pci,netdev=net0"
	-qmp "unix:$dir/qmp.sock,server=on,wait=off"
	-serial "file:$dir/serial.log"
	-no-reboot
)

if [ "$mode" = view ]; then
	args+=(-display "dbus,gl=on")
else
	args+=(-display "egl-headless")
fi

if [ "$action" = print ]; then
	echo "program=qemu-system-x86_64"
	for arg in "${args[@]}"; do
		echo "arg=$arg"
	done
	exit 0
fi

mkdir -p "$dir"
"$VIRTIOFSD" --socket-path="$dir/virtiofsd.sock" --shared-dir="$ROOT" --readonly --cache=never &
vfs=$!
trap 'kill "$vfs" 2>/dev/null || true' EXIT

qemu-system-x86_64 "${args[@]}"
