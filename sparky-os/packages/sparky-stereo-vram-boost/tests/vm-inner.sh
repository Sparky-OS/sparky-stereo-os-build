#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/25
# Runs at boot inside vm-proof.sh's system; prints PROOF| lines on the console.
p() { echo "PROOF|$*"; }
p "kernel|$(uname -r)"
p "controllers|$(cat /sys/fs/cgroup/cgroup.controllers)"
p "dmem.capacity|$(tr '\n' ';' < /sys/fs/cgroup/dmem.capacity 2>/dev/null || echo absent)"
p "decision|$(tr '\n' ';' < /run/sparky-stereo-vram-boost/state 2>/dev/null || echo 'no state')"
p "decider|$(systemctl show -p ActiveState -p Result sparky-stereo-vram-boost.service | tr '\n' ' ')"
p "booster-system|$(systemctl show -p ActiveState -p ConditionResult dmemcg-booster-system.service | tr '\n' ' ')"
for c in / /system.slice /user.slice; do p "subtree-before|$c|$(cat /sys/fs/cgroup$c/cgroup.subtree_control 2>/dev/null)"; done
timeout 5 /usr/bin/dmemcg-booster --use-system-bus >/run/booster.out 2>&1
p "booster-by-hand|exit $?|$(head -c 300 /run/booster.out | tr '\n' ' ')"
for c in / /system.slice /user.slice; do p "subtree-after|$c|$(cat /sys/fs/cgroup$c/cgroup.subtree_control 2>/dev/null)"; done
p "dmem-files|$(ls /sys/fs/cgroup/system.slice/ | grep '^dmem\.' | tr '\n' ' ')"
# the gate open (as the decision would leave it on a machine with an AMD GPU with its own VRAM): the system unit starts
: > /run/sparky-stereo-vram-boost/enabled
systemctl start dmemcg-booster-system.service; sleep 3
p "gate-open-system|$(systemctl show -p ActiveState -p ConditionResult dmemcg-booster-system.service | tr '\n' ' ')"
for c in / /system.slice /user.slice; do p "subtree-gate-open|$c|$(cat /sys/fs/cgroup$c/cgroup.subtree_control 2>/dev/null)"; done
# a lingering user and the session unit, gate open, then closed again
useradd -m -u 1000 proof 2>/dev/null; loginctl enable-linger proof
for i in $(seq 1 30); do systemctl is-active -q user@1000.service && break; sleep 1; done
runuser -u proof -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user start dmemcg-booster-user.service; sleep 3
p "gate-open-user|$(runuser -u proof -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user show -p ActiveState -p ConditionResult dmemcg-booster-user.service | tr '\n' ' ')"
u=/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service
p "user-subtree|user-1000.slice:$(cat /sys/fs/cgroup/user.slice/user-1000.slice/cgroup.subtree_control) user@1000.service:$(cat $u/cgroup.subtree_control 2>/dev/null) app.slice:$(cat $u/app.slice/cgroup.subtree_control 2>/dev/null)"
p "user-dmem.low|$(cat $u/dmem.low 2>/dev/null | tr '\n' ';') app.slice:$(cat $u/app.slice/dmem.low 2>/dev/null | tr '\n' ';')"
runuser -u proof -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user stop dmemcg-booster-user.service
rm -f /run/sparky-stereo-vram-boost/enabled
runuser -u proof -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user start dmemcg-booster-user.service; sleep 1
p "gate-closed-user|$(runuser -u proof -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user show -p ActiveState -p ConditionResult dmemcg-booster-user.service | tr '\n' ' ')"
p "done"
