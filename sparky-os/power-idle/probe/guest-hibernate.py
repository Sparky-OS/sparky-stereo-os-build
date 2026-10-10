#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Guest-only hibernate and resume probe, in two phases across the resume.

guest-hibernate.py arm OUT.json [--negative] [--no-hibernate]
    Check the configuration the installer must create, record a witness,
    then ask logind to hibernate (the VM powers off). --negative plants one
    break (the kernel's resume device cleared) and must be caught (exit 1).
guest-hibernate.py verify OUT.json
    After the VM is started again: the same kernel instance must have
    resumed (boot id, a token kept only in RAM, the witness process).
Exit 0 when everything matches, 1 on a mismatch, 2 when the probe itself
cannot run. Run as root in a disposable VM, never on a host or a container.
"""

import argparse
import json
import os
import re
import secrets
import subprocess
import sys
import time
from pathlib import Path

STATE = Path("/var/lib/sparky-hibernate-probe/state.json")
TOKEN = Path("/dev/shm/sparky-hibernate-probe-token")
EFI_SECURE_BOOT = Path("/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c")


class Mismatch(Exception):
    pass


def command(*arguments, check=True):
    result = subprocess.run(arguments, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise RuntimeError(f"{' '.join(arguments)}: {result.stderr.strip()}")
    return result.stdout.strip()


def meminfo():
    return {line.split(":")[0]: int(line.split()[1]) for line in Path("/proc/meminfo").read_text().splitlines()}


def secure_boot():
    if not Path("/sys/firmware/efi").exists():
        return {"firmware": "bios", "secure_boot": False}
    if not EFI_SECURE_BOOT.exists():
        return {"firmware": "uefi", "secure_boot": False, "note": "no SecureBoot variable (firmware without Secure Boot)"}
    data = EFI_SECURE_BOOT.read_bytes()
    lockdown = Path("/sys/kernel/security/lockdown")
    return {"firmware": "uefi", "secure_boot": data[-1] == 1,
            "lockdown": lockdown.read_text().strip() if lockdown.exists() else None}


def area():
    """The Cushion Swap File's area: AREA= in /etc/default/cushion-swap, else the first noauto swap line of fstab."""
    settings = Path("/etc/default/cushion-swap")
    if settings.exists():
        for line in settings.read_text().splitlines():
            match = re.match(r"\s*AREA=[\"']?([^\"'#\s]+)", line)
            if match:
                return match[1]
    for line in Path("/etc/fstab").read_text().splitlines():
        fields = line.split()
        if len(fields) >= 4 and not fields[0].startswith("#") and fields[2] == "swap" and "noauto" in fields[3].split(","):
            return fields[0]
    return None


def physical_offset(path, filesystem):
    """resume_offset for a swap file: its first page on the device, in pages."""
    if filesystem == "btrfs":
        return int(command("btrfs", "inspect-internal", "map-swapfile", "-r", path))
    for line in command("filefrag", "-v", "-b4096", path).splitlines():
        match = re.match(r"\s*0:\s+0\.\.\s*\d+:\s+(\d+)\.\.", line)
        if match:
            return int(match[1])
    raise RuntimeError("no first extent for " + path)


def can_hibernate(user=None):
    words = ["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1",
             "org.freedesktop.login1.Manager", "CanHibernate"]
    if user:
        words = ["runuser", "-u", user, "--"] + words
    return command(*words).split()[-1].strip('"')


def kde_can_hibernate(user):
    """What the Plasma session offers: PowerDevil's org.freedesktop.PowerManagement.CanHibernate."""
    if not user:
        return None
    uid = int(command("id", "-u", user))
    output = command("runuser", "-u", user, "--", "env", f"XDG_RUNTIME_DIR=/run/user/{uid}",
                     f"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus", "busctl", "--user", "call",
                     "org.freedesktop.PowerManagement", "/org/freedesktop/PowerManagement",
                     "org.freedesktop.PowerManagement", "CanHibernate", check=False)
    return output.split()[-1] if output else None


def swaps():
    lines = Path("/proc/swaps").read_text().splitlines()[1:]
    return [{"name": fields[0], "size_kib": int(fields[2]), "used_kib": int(fields[3]), "priority": int(fields[4])}
            for fields in (line.split() for line in lines)]


def configuration(result, negative):
    checks = result.setdefault("checks", {})
    memory = meminfo()
    swap_area = area()
    if not swap_area:
        raise Mismatch("No Cushion Swap File area (AREA= or a noauto swap line in /etc/fstab)")
    path = Path(swap_area)
    filesystem = command("findmnt", "-n", "-o", "FSTYPE", "-T", swap_area)
    source = command("findmnt", "-n", "-o", "SOURCE", "-T", swap_area).split("[")[0]
    size_kib = path.stat().st_size // 1024
    checks["area"] = {"path": swap_area, "file_system": filesystem, "size_kib": size_kib, "mem_total_kib": memory["MemTotal"]}
    if size_kib < memory["MemTotal"]:
        raise Mismatch(f"The swap area ({size_kib} KiB) is smaller than RAM ({memory['MemTotal']} KiB)")
    if any(entry["name"] == swap_area for entry in swaps()):
        raise Mismatch("The swap area is already on; it must be off at rest")
    if filesystem == "btrfs":
        attributes = command("lsattr", swap_area).split()[0]
        checks["area"]["btrfs_no_copy_on_write"] = "C" in attributes
        if "C" not in attributes:
            raise Mismatch("A Btrfs swap file needs no copy-on-write (btrfs filesystem mkswapfile)")

    cmdline = Path("/proc/cmdline").read_text()
    resume = re.search(r"(?:^|\s)resume=(\S+)", cmdline)
    offset = re.search(r"(?:^|\s)resume_offset=(\d+)", cmdline)
    expected_offset = physical_offset(swap_area, filesystem)
    device = os.stat(source).st_rdev
    devno = f"{os.major(device)}:{os.minor(device)}"
    if negative:
        Path("/sys/power/resume").write_text("0:0")
        result["negative_injected"] = Path("/sys/power/resume").read_text().strip() == "0:0"
    kernel_resume = Path("/sys/power/resume").read_text().strip()
    kernel_offset = int(Path("/sys/power/resume_offset").read_text())
    checks["resume"] = {"cmdline": resume[1] if resume else None, "cmdline_offset": int(offset[1]) if offset else None,
                        "file_offset": expected_offset, "kernel_resume": kernel_resume, "kernel_offset": kernel_offset,
                        "device": source, "devno": devno}
    if not resume or not offset:
        raise Mismatch("resume= and resume_offset= must be on the kernel command line")
    if int(offset[1]) != expected_offset or kernel_offset != expected_offset:
        raise Mismatch(f"resume_offset {offset[1]} / kernel {kernel_offset} is not the file's offset {expected_offset}")
    if kernel_resume != devno:
        raise Mismatch(f"The kernel's resume device is {kernel_resume}, the swap area is on {devno}")

    initramfs = Path("/etc/initramfs-tools/conf.d/resume")
    image = Path(f"/boot/initrd.img-{os.uname().release}")
    listing = command("lsinitramfs", str(image)) if image.exists() else ""
    checks["initramfs"] = {"conf": initramfs.read_text().strip() if initramfs.exists() else None,
                           "image": str(image), "resume_script": "scripts/local-premount/resume" in listing,
                           "resume_conf_in_image": "conf/conf.d/resume" in listing}
    if not checks["initramfs"]["resume_script"] or not checks["initramfs"]["resume_conf_in_image"]:
        raise Mismatch("The initramfs has no resume script or no resume configuration")

    zram = [entry for entry in swaps() if entry["name"].startswith("/dev/zram")]
    checks["zram"] = {"devices": zram, "note": "the area takes the kernel's next negative priority when switched on"}
    if zram and any(entry["priority"] < 0 for entry in zram):
        raise Mismatch("zram must come before the disk swap (a positive priority)")

    checks["can_hibernate"] = {"root": can_hibernate(), "session_user": can_hibernate(result.get("user")),
                               "kde": kde_can_hibernate(result.get("user"))}
    if checks["can_hibernate"]["root"] != "yes" or checks["can_hibernate"]["session_user"] not in ("yes", "challenge"):
        raise Mismatch(f"logind does not offer Hibernate: {checks['can_hibernate']}")
    if checks["can_hibernate"]["kde"] != "true":
        raise Mismatch(f"KDE (PowerDevil) does not offer Hibernate: {checks['can_hibernate']}")


def arm(args, result):
    sessions = [line.split() for line in command("loginctl", "list-sessions", "--no-legend").splitlines()]
    seat = [fields for fields in sessions if len(fields) > 3 and fields[3] == "seat0"]
    result["user"] = seat[0][2] if seat else None
    result["secure_boot"] = secure_boot()
    try:
        configuration(result, args.negative)
    finally:
        if args.negative:
            Path("/sys/power/resume").write_text(result["checks"]["resume"]["devno"])
    if args.negative:
        raise RuntimeError("The planted break was not detected")
    token = secrets.token_hex(16)
    TOKEN.write_text(token)
    # A process in its own unit, so it outlives this one: it must still be there after the resume.
    command("systemd-run", "--unit=sparky-hibernate-witness", "--collect", "--property=Type=exec", "sleep", "infinity")
    witness_pid = int(command("systemctl", "show", "-p", "MainPID", "--value", "sparky-hibernate-witness.service"))
    state = {"boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(), "token": token,
             "witness_pid": witness_pid, "armed_at": time.time(), "uptime": float(Path("/proc/uptime").read_text().split()[0])}
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state))
    result["armed"] = state
    if args.no_hibernate:
        return
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    os.sync()
    command("systemctl", "hibernate", "--no-block")


def verify(args, result):
    if not STATE.exists():
        raise RuntimeError("Not armed: run the arm phase first")
    state = json.loads(STATE.read_text())
    boot_id = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    witness_alive = Path(f"/proc/{state['witness_pid']}").exists()
    token = TOKEN.read_text() if TOKEN.exists() else None
    journal = command("journalctl", "-b", "-q", "--no-pager", "-o", "cat", "--since", f"@{int(state['armed_at'])}", check=False)
    result["resume"] = {
        "boot_id_unchanged": boot_id == state["boot_id"],
        "token_in_ram": token == state["token"],
        "witness_alive": witness_alive,
        "journal": [line for line in journal.splitlines()
                    if re.search(r"hibernat|PM: |resume|Cushion Swap File|cushion-swap", line, re.I)][:40],
        "swaps_after": swaps(),
        "can_hibernate_after": can_hibernate(),
        "secure_boot": secure_boot(),
    }
    command("systemctl", "stop", "sparky-hibernate-witness.service", check=False)
    STATE.unlink()
    TOKEN.unlink(missing_ok=True)
    if not (result["resume"]["boot_id_unchanged"] and result["resume"]["token_in_ram"] and witness_alive):
        raise Mismatch("The machine did not resume from hibernation: this is a fresh boot")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("phase", choices=("arm", "verify"))
    parser.add_argument("output", type=Path)
    parser.add_argument("--negative", action="store_true")
    parser.add_argument("--no-hibernate", action="store_true")
    args = parser.parse_args()
    result = {"phase": args.phase, "negative": args.negative, "failure": None, "verified": False}
    status = 0
    try:
        if os.geteuid() != 0 or Path("/.dockerenv").exists():
            raise RuntimeError("Run as root in the disposable guest, never a container or the host")
        command("systemd-detect-virt", "--vm")
        (arm if args.phase == "arm" else verify)(args, result)
        result["verified"] = True
    except Mismatch as error:
        result["failure"] = str(error)
        result["negative_detected"] = bool(result.get("negative_injected"))
        status = 1
    except Exception as error:
        result["failure"] = str(error)
        status = 2
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    return status


if __name__ == "__main__":
    sys.exit(main())
