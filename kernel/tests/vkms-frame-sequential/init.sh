#!/bin/busybox sh
# SPDX-License-Identifier: GPL-2.0-only
# PID 1 of the vkms-frame-sequential guest. Builds a VKMS device in configfs with two DisplayPort connectors that
# read the same EDID (/data/dp-fs.bin, frame-sequential 640x480 declared): dp0 on crtc0, with writeback, opted in to
# frame-sequential stereo; dp1 on crtc1, not opted in. Then runs IGT's kms_frame_sequential from the root shared over
# 9p (tag "root"), with the arguments of fs.args= on the kernel command line, and saves the stereo link logs.
# Results go to the serial console as FS| lines.
export PATH=/bin:/sbin
/bin/busybox --install -s /bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null
mount -t tmpfs tmpfs /tmp
mount -t configfs configfs /sys/kernel/config
mount -t debugfs debugfs /sys/kernel/debug
exec 0</dev/console 1>/dev/console 2>&1
args=
for a in $(cat /proc/cmdline); do
	case "$a" in fs.args=*) args=$(echo "${a#fs.args=}" | tr , ' ') ;; esac
done
echo "FS|kernel|$(cat /proc/version)"
mkdir -p /out /r
mount -t 9p -o trans=virtio,version=9p2000.L out /out || echo "FS|error|no output share"

d=/sys/kernel/config/vkms/fs
mk() { mkdir "$1" || echo "FS|error|mkdir $1"; }
put() { printf '%s' "$2" > "$1" || echo "FS|error|write $2 to $1"; }
mk $d
for i in 0 1; do
	mk $d/planes/primary$i; put $d/planes/primary$i/type 1
	mk $d/crtcs/crtc$i
	mk $d/encoders/encoder$i
	mk $d/connectors/dp$i
	ln -s $d/crtcs/crtc$i $d/planes/primary$i/possible_crtcs/crtc$i
	ln -s $d/crtcs/crtc$i $d/encoders/encoder$i/possible_crtcs/crtc$i
	put $d/connectors/dp$i/type 10
	cat /data/dp-fs.bin > $d/connectors/dp$i/edid || echo "FS|error|edid of dp$i"
	put $d/connectors/dp$i/edid_enabled 1
	ln -s $d/encoders/encoder$i $d/connectors/dp$i/possible_encoders/encoder$i
done
put $d/crtcs/crtc0/writeback 1
put $d/connectors/dp0/stereo_frame_sequential 1
put $d/enabled 1
echo "FS|device|enabled=$(cat $d/enabled)"
for c in $d/connectors/*; do
	echo "FS|connector|${c##*/}|type=$(cat $c/type 2>/dev/null)|edid_enabled=$(cat $c/edid_enabled 2>/dev/null)|stereo_frame_sequential=$(cat $c/stereo_frame_sequential 2>/dev/null)"
done
for m in /sys/class/drm/card*-*/modes; do echo "FS|sysfs-modes|$m|$(tr '\n' ' ' < $m)"; done

if mount -t 9p -o trans=virtio,version=9p2000.L,ro root /r; then
	mount -t proc proc /r/proc
	mount -t sysfs sysfs /r/sys
	mount -t debugfs debugfs /r/sys/kernel/debug
	mount -t devtmpfs devtmpfs /r/dev
	mount -t tmpfs tmpfs /r/tmp
	for t in mode-listed refused-without-opt-in writeback-eye-order crc-eye-order flip-at-pair-boundary 2d-control; do
		chroot /r /usr/bin/env IGT_FORCE_DRIVER=vkms /usr/local/bin/kms_frame_sequential $args --run-subtest $t > /tmp/igt.log 2>&1
		rc=$?
		cat /tmp/igt.log
		cp /tmp/igt.log /out/igt-$t.log 2>/dev/null
		echo "FS|igt|$t|exit=$rc"
		for l in /sys/kernel/debug/dri/*/crtc-*/stereo_link; do
			n=$(echo "$l" | tr / _)
			cp "$l" "/out/link-$t$n.txt" 2>/dev/null
		done
	done
else
	echo "FS|error|no IGT root shared"
fi
if [ -w /sys/kernel/debug/kmemleak ]; then
	echo scan > /sys/kernel/debug/kmemleak
	sleep 6
	echo scan > /sys/kernel/debug/kmemleak
	cat /sys/kernel/debug/kmemleak > /out/kmemleak.txt
	echo "FS|kmemleak|$(grep -c 'unreferenced object' /out/kmemleak.txt) unreferenced objects"
fi
echo "FS|done"
sync
umount /out 2>/dev/null
poweroff -f
