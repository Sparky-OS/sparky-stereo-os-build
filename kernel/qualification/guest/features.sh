# Kernel feature probes of the Sparky Stereo OS kernel, for hibernate-bench's "custom" scenario (--guest-script). Runs in the guest as the phase script (BusyBox sh),
# sourced by /init after /bench/lib.sh. The host passes --load-modules "virtio_blk binder_linux ntsync tcp_bbr3 adios" so those are loaded before this runs.
ok()  { bench_check "$1" PASS "$2"; }
bad() { bench_check "$1" FAIL "$2"; }
inf() { bench_check "$1" INFO "$2"; }

bench_info release "$(uname -r)"
bench_info uname_v "$(uname -v)"

# Secure Boot and signatures: all of the modules above were loaded under Secure Boot, so the build's key verified them
sb=$(dd if=/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c bs=1 skip=4 count=1 2>/dev/null | hexdump -v -e '1/1 "%u"')
[ "$sb" = 1 ] && ok secure_boot "firmware SecureBoot=1" || inf secure_boot "SecureBoot variable: ${sb:-unreadable}"
for m in virtio_blk binder_linux ntsync tcp_bbr3 adios; do
    if grep -q "^$m " /proc/modules; then ok "module_$m" "loaded"; else bad "module_$m" "not loaded"; fi
done

# BTF: vmlinux and modules (the loaded modules appear under /sys/kernel/btf when module BTF was generated)
if [ -e /sys/kernel/btf/vmlinux ]; then ok btf_vmlinux "$(wc -c < /sys/kernel/btf/vmlinux) bytes"; else bad btf_vmlinux "/sys/kernel/btf/vmlinux is missing"; fi
mb=$(ls /sys/kernel/btf 2>/dev/null | grep -v '^vmlinux$' | tr '\n' ' ')
[ -n "$mb" ] && ok btf_modules "$mb" || bad btf_modules "no module BTF under /sys/kernel/btf"

# schedulers: BORE, POC selector, sched_ext
for k in sched_bore sched_poc_selector; do
    v=$(cat /proc/sys/kernel/$k 2>/dev/null)
    [ -n "$v" ] && ok "sysctl_$k" "kernel.$k=$v" || bad "sysctl_$k" "kernel.$k is missing"
done
if [ -d /sys/kernel/sched_ext ]; then ok sched_ext_present "state=$(cat /sys/kernel/sched_ext/state 2>/dev/null)"; else bad sched_ext_present "no /sys/kernel/sched_ext"; fi
inf preempt_model "$(cat /sys/kernel/debug/sched/preempt 2>/dev/null || echo 'debugfs sched/preempt not readable')"
# Linux 7.3's cgroup scheduling (Peter Zijlstra's "sched: Flatten the pick"): the group share mode in debugfs, concur by default
# (kernel/sched/debug.c cgroup_mode = 2, "up smp concur max tasks"); BORE (series 10) must leave it in place
cm=$(cat /sys/kernel/debug/sched/cgroup_mode 2>/dev/null)
case "$cm" in *"(concur)"*) ok sched_cgroup_mode "$cm";; *) bad sched_cgroup_mode "sched/cgroup_mode: ${cm:-not readable}";; esac

# The dmem cgroup controller (CONFIG_CGROUP_DMEM, build 13 on): listed at the root, and a child gets dmem.min, dmem.low and dmem.max once it is enabled
mkdir -p /sys/fs/cgroup
grep -qw cgroup2 /proc/mounts || mount -t cgroup2 cgroup2 /sys/fs/cgroup 2>/run/cg.err
ctl=$(cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null)
case " $ctl " in *" dmem "*) ok cgroup_dmem "controllers: $ctl";; *) bad cgroup_dmem "controllers: ${ctl:-none} $(cat /run/cg.err 2>/dev/null)";; esac
if echo +dmem > /sys/fs/cgroup/cgroup.subtree_control 2>/run/cg.err && mkdir -p /sys/fs/cgroup/sparky-dmem-probe; then
    f=$(cd /sys/fs/cgroup/sparky-dmem-probe && ls -d dmem.* 2>/dev/null | tr '\n' ' ')
    case " $f " in *" dmem.low "*" dmem.max "*" dmem.min "*|*" dmem.low "*" dmem.min "*) ok cgroup_dmem_files "$f; capacity: $(tr '\n' ';' < /sys/fs/cgroup/dmem.capacity 2>/dev/null)";; *) bad cgroup_dmem_files "child files: $f";; esac
    rmdir /sys/fs/cgroup/sparky-dmem-probe; echo -dmem > /sys/fs/cgroup/cgroup.subtree_control
else
    bad cgroup_dmem_files "enabling dmem in the root's subtree_control failed: $(cat /run/cg.err)"
fi

# Binder: with binderfs built in (CONFIG_ANDROID_BINDERFS=y) the legacy /dev/binder nodes are not created; a binderfs mount provides binder, hwbinder and vndbinder
if grep -qw binder /proc/filesystems; then
    mkdir -p /binderfs
    if mount -t binder binder /binderfs 2>/run/b.err; then
        l=$(ls /binderfs | tr '\n' ' ')
        miss=""; for n in binder hwbinder vndbinder binder-control; do case " $l " in *" $n "*) ;; *) miss="$miss $n";; esac; done
        [ -z "$miss" ] && ok binderfs "mounted; nodes: $l" || bad binderfs "mounted but missing:$miss (nodes: $l)"
    else bad binderfs "mount failed: $(cat /run/b.err)"; fi
else bad binderfs "binder is not in /proc/filesystems"; fi

# NTSYNC, BBRv3, ADIOS
[ -e /dev/ntsync ] && ok dev_ntsync "present" || bad dev_ntsync "missing"
cc=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null); case " $cc " in *" bbr3 "*|*" bbr "*) ok tcp_bbr3 "available: $cc";; *) bad tcp_bbr3 "available: $cc";; esac
sched=$(cat /sys/block/vda/queue/scheduler 2>/dev/null); case "$sched" in *adios*) ok io_adios "$sched";; *) inf io_adios "scheduler line: $sched";; esac

# a sched_ext scheduler, if the host gave one (--guest-dir with bin/scx_simple and lib/): load it, check the state, let it run a moment, unload it
if [ -x /guest/bin/scx_simple ]; then
    LD=/guest/lib/ld-linux-x86-64.so.2
    ( timeout 8 $LD --library-path /guest/lib /guest/bin/scx_simple > /run/scx.out 2>&1 ) &
    n=0; st=""
    while [ $n -lt 6 ]; do sleep 1; st=$(cat /sys/kernel/sched_ext/state 2>/dev/null); [ "$st" = enabled ] && break; n=$((n+1)); done
    ops=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null)
    if [ "$st" = enabled ]; then ok sched_ext_load "scx_simple: state=enabled ops=$ops"; else bad sched_ext_load "state=$st; $(head -c 300 /run/scx.out | tr '\n' ' ')"; fi
    wait
    inf sched_ext_after "state=$(cat /sys/kernel/sched_ext/state 2>/dev/null)"
else
    inf sched_ext_load "no scx_simple given (--guest-dir)"
fi
