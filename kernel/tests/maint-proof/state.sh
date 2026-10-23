#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# state.sh LABEL : what the kernel packages left behind
echo "---- $1"
for l in /vmlinuz /vmlinuz.old /initrd.img /initrd.img.old; do
    if [ -L $l ]; then echo "$l -> $(readlink $l)"; elif [ -e $l ]; then echo "$l (not a link)"; else echo "$l absent"; fi
done
echo "/boot: $(ls /boot | tr '\n' ' ')"
echo "fresh-install flags: $(ls /lib/modules/*/.fresh-install 2>/dev/null | tr '\n' ' ')"
echo "hooks:"; sed 's/^/  /' /var/log/kernel-hooks.log; : > /var/log/kernel-hooks.log
