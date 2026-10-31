#!/bin/busybox sh
# SPDX-License-Identifier: GPL-2.0-only
# PID 1 of a guest that checks fs-probe itself on VKMS (series group 38's frame-sequential model): the VKMS device of
# kernel/tests/vkms-frame-sequential/init.sh without writeback, DP-1 opted in to frame-sequential stereo, DP-2 not,
# both reading /data/dp-fs.bin; then fs-probe list, test DP-1, test DP-2 (the refusal), run DP-1. Lines go to the
# serial console; nothing here can reach a real display.
export PATH=/bin:/sbin
/bin/busybox --install -s /bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null
mount -t tmpfs tmpfs /tmp
mount -t configfs configfs /sys/kernel/config
mount -t debugfs debugfs /sys/kernel/debug
exec 0</dev/console 1>/dev/console 2>&1
echo "FS|kernel|$(cat /proc/version)"
d=/sys/kernel/config/vkms/fs
mkdir $d
for i in 0 1; do
	mkdir $d/planes/primary$i; printf 1 > $d/planes/primary$i/type
	mkdir $d/crtcs/crtc$i $d/encoders/encoder$i $d/connectors/dp$i
	ln -s $d/crtcs/crtc$i $d/planes/primary$i/possible_crtcs/crtc$i
	ln -s $d/crtcs/crtc$i $d/encoders/encoder$i/possible_crtcs/crtc$i
	printf 10 > $d/connectors/dp$i/type
	cat /data/dp-fs.bin > $d/connectors/dp$i/edid
	printf 1 > $d/connectors/dp$i/edid_enabled
	ln -s $d/encoders/encoder$i $d/connectors/dp$i/possible_encoders/encoder$i
done
printf 1 > $d/connectors/dp0/stereo_frame_sequential
printf 1 > $d/enabled
echo "FS|device|enabled=$(cat $d/enabled)"
for step in "list 0" "test 0 DP-1" "test 0 DP-2" "run 0 DP-1"; do
	echo "FS|step|$step"
	/bin/fs-probe $step
	echo "FS|exit|$step|$?"
done
echo "FS|done"
poweroff -f
