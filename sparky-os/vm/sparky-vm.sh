#!/bin/bash
# The Sparky Stereo OS development VM: an installed Sparky KDE where the edition is
# assembled and its ISOs are packed with Sparky's own tool. Generous on purpose (Daniel,
# 2026-10-02: the whole machine is for this work): 10 of the 12 threads (two stay as the
# host's safe lane, Daniel), 64 GB of RAM.
# The VM's disk lives on / (the faster NVMe, room to grow); the repo, packages and ISO
# outputs stay on /K3D and are shared into the VM over virtiofs.
#
#   sparky-vm.sh create            disk image and UEFI variables, once
#   sparky-vm.sh install [iso]     boot the Sparky KDE ISO to install it
#   sparky-vm.sh run               boot the installed system
#   sparky-vm.sh ssh [command]     a shell in the VM (port 2222 on the host)
#   sparky-vm.sh compact           (VM powered off) rewrite the disk image without its freed
#                                  clusters, after prepack.sh's TRIM
#
# GPU=nvidia passes the RTX 3060 (01:00.0 and its audio 01:00.1) through, for test
# sessions of the stereo stack on real hardware; the card must be bound to vfio-pci
# first (sudo gpu-vfio.sh give, with KWin on the iGPU only). Without it the VM gets a virtual
# GPU drawn by the host (virgl).
# HEADLESS=1 opens no window on the host's desktop (virtual GPU, no display): for test
# sessions driven over ssh while nobody is at the screens.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail

VMDIR=${VMDIR:-/srv/sparky-vm}
DISK=$VMDIR/sparky-dev.qcow2
VARS=$VMDIR/OVMF_VARS_4M.fd
ISO_DEFAULT=${SPARKY_SCRATCH:?}/sparky-os/iso/sparkylinux-2026.09-x86_64-kde.iso
CPUS=${CPUS:-10}
MEM=${MEM:-64G}
DISK_SIZE=${DISK_SIZE:-240G}
# Shared into the VM (tag:host path); mount in the VM with
#   mount -t virtiofs <tag> <dir>
SHARES=(
	"sparky-os:$(cd "$(dirname "$0")/.." && pwd)"
	"sparky-work:${SPARKY_SCRATCH:?}/sparky-os"
)

# The desktop session's display, not this shell's (which may point elsewhere).
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}

create() {
	[ -e "$DISK" ] && { echo "exists: $DISK"; exit 1; }
	qemu-img create -f qcow2 -o cluster_size=2M,lazy_refcounts=on "$DISK" "$DISK_SIZE"
	cp /usr/share/OVMF/OVMF_VARS_4M.fd "$VARS"
	# The key this host uses to work in the VM; vm-setup.sh (run once in the VM) trusts it.
	ssh-keygen -q -t ed25519 -N '' -C sparky-dev-vm -f "$VMDIR/id_ed25519"
	cp "$VMDIR/id_ed25519.pub" ${SPARKY_SCRATCH:?}/sparky-os/vm-ssh.pub
}

start_shares() {
	local s tag dir sock
	for s in "${SHARES[@]}"; do
		tag=${s%%:*} dir=${s#*:} sock=$VMDIR/fs-$tag.sock
		mkdir -p "$dir"
		rm -f "$sock"
		/usr/libexec/virtiofsd --socket-path="$sock" --shared-dir="$dir" \
			--sandbox=none --cache=auto --announce-submounts >"$VMDIR/fs-$tag.log" 2>&1 &
		QEMU_SHARES+=(-chardev "socket,id=fs-$tag,path=$sock"
			-device "vhost-user-fs-pci,queue-size=1024,chardev=fs-$tag,tag=$tag")
	done
	for s in "${SHARES[@]}"; do
		sock=$VMDIR/fs-${s%%:*}.sock
		for _ in $(seq 50); do [ -S "$sock" ] && break; sleep 0.1; done
	done
}

boot() {
	local extra=("$@") gpu=()
	QEMU_SHARES=()
	start_shares
	if [ "${GPU:-}" = nvidia ]; then
		# the card's HDMI port is the VM's screen; the virtual GPU stays for the boot console,
		# shown in a window only when HEADLESS is not set
		gpu=(-device vfio-pci,host=01:00.0,multifunction=on -device vfio-pci,host=01:00.1
			-vga none -device virtio-gpu-pci -display "$([ "${HEADLESS:-}" = 1 ] && echo none || echo gtk)")
		# the card reaches guest memory directly, so all of it must be locked
		sudo -n prlimit --pid $$ --memlock=unlimited:unlimited
	elif [ "${HEADLESS:-}" = 1 ]; then
		gpu=(-device virtio-vga -display none)
	else
		gpu=(-device virtio-vga-gl -display gtk,gl=on)
	fi
	qemu-system-x86_64 -name sparky-dev \
		-machine q35,accel=kvm -cpu host,topoext=on \
		-smp "$CPUS",sockets=1,cores=$((CPUS / 2)),threads=2 -m "$MEM" \
		-object memory-backend-memfd,id=mem,size="$MEM",share=on -numa node,memdev=mem \
		-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
		-drive if=pflash,format=raw,file="$VARS" \
		-drive file="$DISK",if=none,id=disk0,format=qcow2,cache=none,aio=io_uring,discard=unmap \
		-device virtio-blk-pci,drive=disk0,bootindex=1 \
		-netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22 -device virtio-net-pci,netdev=n0 \
		-audiodev pipewire,id=snd0 -device ich9-intel-hda -device hda-output,audiodev=snd0 \
		-device qemu-xhci -device usb-tablet \
		"${gpu[@]}" "${QEMU_SHARES[@]}" "${extra[@]}"
	kill $(jobs -p) 2>/dev/null || true
}

case ${1:-} in
create) create ;;
install) boot -drive file="${2:-$ISO_DEFAULT}",media=cdrom,readonly=on,if=none,id=cd0 \
	-device ide-cd,drive=cd0,bootindex=0 ;;
run) boot ;;
compact) pgrep -f "qemu-system-x86_64 -name sparky-dev" >/dev/null && { echo "power the VM off first"; exit 1; }
	qemu-img convert -p -O qcow2 -o cluster_size=2M,lazy_refcounts=on "$DISK" "$DISK.compact" &&
		mv "$DISK.compact" "$DISK" && ls -la "$DISK" ;;
ssh) shift; exec ssh -p 2222 -i "$VMDIR/id_ed25519" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$VMDIR/known_hosts" \
	"${VMUSER:-daniel}"@127.0.0.1 "$@" ;;
*) sed -n '2,21p' "$0"; exit 1 ;;
esac
