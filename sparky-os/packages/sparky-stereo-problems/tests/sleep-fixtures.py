#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/09
# Copyright 2026 under the GNU GPL3 License
# ORDER 446: journal exports of failed sleep attempts, for sleep-tests.sh (systemd-journal-remote turns each into a journal
# folder). The shapes are the real ones, captured from a guest whose hibernation a virtio-fs share refused
# (fixtures/virtiofs-real.export): systemd-sleep's lines with SYSLOG_IDENTIFIER=systemd-sleep, its SLEEP_STOP message with
# ERRNO=, the unit's lines with INVOCATION_ID, the kernel's with _TRANSPORT=kernel and _KERNEL_DEVICE. Each kernel text
# is the format string of the kernel's source (the file and function are named beside it).
# Usage: sleep-fixtures.py SCENARIO UNIT OUTFILE
import sys

BOOT = "494902b537c34e5cb90fc13438456317"
INV = "2dd21a977b334a18b8e84fd6cbbe4269"
SLEEP_START = "6bbd95ee977941e497c48be27c254128"
SLEEP_STOP = "8811e6df2a8e40f58a94cea26f8ebf14"
T0 = 1794260442000000
mono = 48000000


def entry(t, **f):
    global mono
    mono += 1000
    base = {"__REALTIME_TIMESTAMP": str(T0 + t), "__MONOTONIC_TIMESTAMP": str(mono), "_BOOT_ID": BOOT, "_MACHINE_ID": "0" * 32,
            "_HOSTNAME": "sparky"}
    base.update(f)
    return "\n".join(f"{k}={v}" for k, v in base.items()) + "\n\n"


def starting(t, unit):
    return entry(t, PRIORITY="6", SYSLOG_IDENTIFIER="systemd", _TRANSPORT="journal", MESSAGE=f"Starting {unit} - sleep...",
                 UNIT=unit, INVOCATION_ID=INV, _SYSTEMD_UNIT="init.scope")


def sysleep(t, prio, msg, unit, **extra):
    return entry(t, PRIORITY=str(prio), SYSLOG_IDENTIFIER="systemd-sleep", _TRANSPORT="journal", MESSAGE=msg,
                 _SYSTEMD_UNIT=unit, _SYSTEMD_INVOCATION_ID=INV, _COMM="systemd-sleep", **extra)


def stop_error(t, unit, op, errno, text):
    return sysleep(t, 3, f"Failed to put system to sleep. System resumed again: {text}", unit, MESSAGE_ID=SLEEP_STOP, SLEEP=op, ERRNO=str(errno))


def kernel(t, msg, prio=3, device=None):
    f = dict(PRIORITY=str(prio), SYSLOG_IDENTIFIER="kernel", _TRANSPORT="kernel", MESSAGE=msg)
    if device:
        sub, dev = device
        f["_KERNEL_SUBSYSTEM"] = sub
        f["_KERNEL_DEVICE"] = "+" + sub + ":" + dev
    return entry(t, **f)


def failed(t, unit):
    return entry(t, PRIORITY="3", SYSLOG_IDENTIFIER="systemd", _TRANSPORT="journal", MESSAGE=f"Failed to start {unit}.", UNIT=unit,
                 INVOCATION_ID=INV, _SYSTEMD_UNIT="init.scope")


def build(scenario, unit):
    op = {"systemd-hibernate.service": "hibernate", "systemd-suspend-then-hibernate.service": "suspend-then-hibernate",
          "systemd-hybrid-sleep.service": "hybrid-sleep"}[unit]
    out = []
    # an earlier attempt's freeze failure, before this one began: it must never be read as this attempt's reason
    if scenario == "older-attempt-only":
        out.append(kernel(-60_000_000, "virtio-pci 0000:00:09.0: PM: failed to freeze async: error -95", device=("pci", "0000:00:09.0")))
    out.append(starting(0, unit))
    out.append(sysleep(300_000, 6, f"Performing sleep operation '{op}'...", unit, MESSAGE_ID=SLEEP_START, SLEEP=op))
    t = 400_000
    if scenario == "virtiofs":
        for d in ("0000:00:05.0", "0000:00:06.0"):
            out.append(kernel(t, "virtio-fs: suspend/resume not yet supported", 4)); t += 1000
        for d in ("0000:00:05.0", "0000:00:06.0"):
            out.append(kernel(t, f"virtio-pci {d}: PM: pci_pm_freeze(): virtio_pci_freeze returns -95", device=("pci", d)))
            out.append(kernel(t + 1, f"virtio-pci {d}: PM: dpm_run_callback(): pci_pm_freeze returns -95", device=("pci", d)))
            out.append(kernel(t + 2, f"virtio-pci {d}: PM: failed to freeze async: error -95", device=("pci", d))); t += 1000
        out.append(stop_error(t, unit, op, 95, "Operation not supported"))
    elif scenario == "device":
        # drivers/base/power/main.c pm_dev_err: a driver whose freeze callback returned -110
        out.append(kernel(t, "snd_hda_intel 0000:00:1f.3: PM: azx_freeze_noirq(): azx_freeze_noirq returns -110", device=("pci", "0000:00:1f.3")))
        out.append(kernel(t + 1, "snd_hda_intel 0000:00:1f.3: PM: failed to freeze: error -110", device=("pci", "0000:00:1f.3")))
        out.append(stop_error(t + 2, unit, op, 110, "Connection timed out"))
    elif scenario == "device-suspend":
        # the same device refusing a suspend (the sleep of suspend-then-hibernate)
        out.append(kernel(t, "xhci_hcd 0000:00:14.0: PM: failed to suspend async: error -16", device=("pci", "0000:00:14.0")))
        out.append(stop_error(t + 1, unit, op, 16, "Device or resource busy"))
    elif scenario == "tasks":
        # kernel/power/process.c try_to_freeze_tasks, then sched_show_task for each task
        out.append(kernel(t, "Freezing user space processes failed after 20.003 seconds (2 tasks refusing to freeze, wq_busy=0):"))
        out.append(kernel(t + 1, "task:firefox         state:D stack:0     pid:4242  tgid:4242  ppid:1      task_flags:0x400000 flags:0x00004002", 6))
        out.append(kernel(t + 2, "task:rsync           state:D stack:0     pid:4300  tgid:4300  ppid:1      task_flags:0x400000 flags:0x00004002", 6))
        out.append(stop_error(t + 3, unit, op, 16, "Device or resource busy"))
    elif scenario == "lockdown":
        # security/lockdown/lockdown.c, and systemd-sleep.c on the refused write of /sys/power/disk
        out.append(kernel(t, "Lockdown: systemd-sleep: hibernation is restricted; see man kernel_lockdown.7", 5))
        out.append(sysleep(t + 1, 3, "Failed to write mode to /sys/power/disk: Operation not permitted", unit, ERRNO="1"))
    elif scenario == "swap-systemd":
        # systemd-sleep.c: find_suitable_hibernation_device returned ENOSPC (hibernate-util.c "No swap space available for hibernation.")
        out.append(sysleep(t, 3, "Failed to find location to hibernate to: No space left on device", unit, ERRNO="28"))
    elif scenario == "swap-kernel":
        # kernel/power/swap.c swsusp_swap_check
        out.append(kernel(t, "PM: Cannot find swap device, try swapon -a"))
        out.append(stop_error(t + 1, unit, op, 19, "No such device"))
    elif scenario == "resume":
        out.append(sysleep(t, 3, "No valid 'resume=' option found, refusing to hibernate.", unit, ERRNO="95"))
    elif scenario == "kernel-line":
        # kernel/power/hibernate.c create_image
        out.append(kernel(t, "PM: hibernation: Some devices failed to power down, aborting"))
        out.append(stop_error(t + 1, unit, op, 5, "Input/output error"))
    elif scenario == "sleep-line":
        out.append(stop_error(t, unit, op, 5, "Input/output error"))
    elif scenario in ("none", "older-attempt-only"):
        pass
    elif scenario == "after-end":
        # a kernel line long after the attempt ended is not its reason
        out.append(kernel(120_000_000, "virtio-pci 0000:00:07.0: PM: failed to freeze async: error -95", device=("pci", "0000:00:07.0")))
    elif scenario == "success":
        out.append(sysleep(t, 6, f"System returned from sleep operation '{op}'.", unit, MESSAGE_ID=SLEEP_STOP, SLEEP=op))
    elif scenario == "fell-back":
        # suspend-then-hibernate: the hibernation step failed, systemd-sleep suspended instead and the service ended well
        out.append(kernel(t, "virtio-pci 0000:00:05.0: PM: failed to freeze async: error -95", device=("pci", "0000:00:05.0")))
        out.append(kernel(t - 1, "virtio-fs: suspend/resume not yet supported", 4))
        out.append(stop_error(t + 1, unit, op, 95, "Operation not supported"))
        out.append(sysleep(t + 2, 5, "Couldn't hibernate, will try to suspend again.", unit))
        out.append(sysleep(t + 3, 6, f"System returned from sleep operation '{op}'.", unit, MESSAGE_ID=SLEEP_STOP, SLEEP=op))
    else:
        sys.exit(f"unknown scenario {scenario}")
    out.append(failed(3_000_000, unit) if scenario != "fell-back" and scenario != "success" else starting(3_000_000, unit))
    out.sort(key=lambda e: int(e.split("__REALTIME_TIMESTAMP=")[1].split("\n")[0]))
    return "".join(out)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    open(sys.argv[3], "w").write(build(sys.argv[1], sys.argv[2]))
