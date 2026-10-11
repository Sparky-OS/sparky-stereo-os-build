#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Guest-only hibernate and resume probe, in two phases across the resume.

guest-hibernate.py arm OUT.json [--expect-source file|cmdline] [--after-retract]
                   [--no-hibernate] [--negative | --negative-dropin | --negative-switch-on]
    Find where the image goes the way the edition says it (the installer's
    /etc/initramfs-tools/conf.d/resume, else resume= on the kernel command
    line), check that the kernel, the initramfs and the package agree with it,
    that the area is off and logind and PowerDevil still offer Hibernate, then
    record a witness and hibernate (the VM powers off).
    --after-retract first has the daemon deploy the area and, with a quiet
    window of 20 s, retract it unused; the journal and the log file must show
    both actions. Planted faults, each must be caught (exit 1):
    --negative clears the kernel's resume device; --negative-dropin takes
    logind's bypass away, as a retraction that removed the generator's drop-in
    would; --negative-switch-on masks cushion-swap-hibernate.service and asks
    for hibernation, which must then fail.
guest-hibernate.py verify OUT.json
    After the VM is started again: the same kernel instance must have
    resumed (boot id, a token kept only in RAM, the witness process), and the
    journal must show the area switched on for the image and off again.
Exit 0 when everything matches, 1 on a mismatch, 2 when the probe itself
cannot run. Run as root in a disposable VM, never on a host or a container.
This probe finds the area on its own (Python, Debian's commands), so it also
checks the package's "cushion-swap --resume-target" against it.
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
RESUME_FILE = Path("/etc/initramfs-tools/conf.d/resume")
SETTINGS = Path("/etc/default/cushion-swap")
LOG_FILE = Path("/var/log/cushion-swap/cushion-swap.log")
DROPIN = Path("/run/systemd/generator/systemd-logind.service.d/50-cushion-swap.conf")
NEGATIVE_DROPIN = Path("/run/systemd/system/systemd-logind.service.d/99-sparky-probe-negative.conf")


class Mismatch(Exception):
    pass


def command(*arguments, check=True, timeout=120):
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout)
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


def cushion_area():
    """The Cushion Swap File's area: AREA= in /etc/default/cushion-swap, else the first noauto swap line of fstab."""
    if SETTINGS.exists():
        for line in SETTINGS.read_text().splitlines():
            match = re.match(r"\s*AREA=[\"']?([^\"'#\s]+)", line)
            if match:
                return match[1]
    for line in Path("/etc/fstab").read_text().splitlines():
        fields = line.split()
        if len(fields) >= 4 and not fields[0].startswith("#") and fields[2] == "swap" and "noauto" in fields[3].split(","):
            return fields[0]
    return None


def fstab_swap_files():
    files = []
    for line in Path("/etc/fstab").read_text().splitlines():
        fields = line.split()
        if len(fields) >= 3 and fields[0].startswith("/") and fields[2] == "swap" and Path(fields[0]).is_file():
            files.append(fields[0])
    return files


def device_path(spec):
    for prefix, folder in (("UUID=", "by-uuid"), ("PARTUUID=", "by-partuuid"), ("LABEL=", "by-label"), ("PARTLABEL=", "by-partlabel")):
        if spec.startswith(prefix):
            return os.path.realpath(f"/dev/disk/{folder}/{spec[len(prefix):]}")
    return os.path.realpath(spec)


def devno(path):
    device = os.stat(path).st_rdev
    return f"{os.major(device)}:{os.minor(device)}"


def source_device(path):
    return command("findmnt", "-n", "-o", "SOURCE", "-T", path).split("[")[0]


def physical_offset(path):
    """resume_offset for a swap file: its first page on the device, in pages."""
    if command("findmnt", "-n", "-o", "FSTYPE", "-T", path) == "btrfs":
        return int(command("btrfs", "inspect-internal", "map-swapfile", "-r", path))
    for line in command("filefrag", "-v", f"-b{os.sysconf('SC_PAGE_SIZE')}", path).splitlines():
        match = re.match(r"\s*0:\s+0\.\.\s*\d+:\s+(\d+)\.\.", line)
        if match:
            return int(match[1])
    raise RuntimeError("no first extent for " + path)


def resume_config():
    """Where the image goes: the installer's file first, then the kernel command line."""
    words = Path("/proc/cmdline").read_text().split()
    cmd_resume = next((word[len("resume="):] for word in words if word.startswith("resume=")), None)
    cmd_offset = next((word[len("resume_offset="):] for word in words if word.startswith("resume_offset=")), None)
    spec = file_offset = source = None
    if RESUME_FILE.exists():
        for line in RESUME_FILE.read_text().splitlines():
            match = re.match(r"\s*RESUME=[\"']?([^\"'\s#]*)", line)
            if match:
                spec, source = match[1], str(RESUME_FILE)
            match = re.match(r"\s*RESUME_OFFSET=[\"']?(\d+)", line)
            if match:
                file_offset = match[1]
    if source is None and cmd_resume:
        spec, source, file_offset = cmd_resume, "kernel command line", None
    offset = int(cmd_offset or file_offset or 0)
    return {"source": source, "resume": spec, "offset": offset, "file": RESUME_FILE.read_text().strip() if RESUME_FILE.exists() else None,
            "cmdline_resume": cmd_resume, "cmdline_offset": cmd_offset, "noresume": "noresume" in words}


def resume_target(config):
    device = device_path(config["resume"])
    if not config["offset"]:
        return {"kind": "device", "target": device, "devno": devno(device), "size_kib": int(Path(f"/sys/class/block/{os.path.basename(device)}/size").read_text()) // 2}
    candidates = [path for path in [cushion_area()] + fstab_swap_files() if path and Path(path).is_file()]
    for path in dict.fromkeys(candidates):
        if os.path.realpath(source_device(path)) == device and physical_offset(path) == config["offset"]:
            return {"kind": "file", "target": path, "devno": devno(device), "size_kib": Path(path).stat().st_size // 1024}
    raise Mismatch(f"No swap file on {device} starts at page {config['offset']} (searched {candidates})")


def swaps():
    lines = Path("/proc/swaps").read_text().splitlines()[1:]
    return [{"name": fields[0], "size_kib": int(fields[2]), "used_kib": int(fields[3]), "priority": int(fields[4])}
            for fields in (line.split() for line in lines)]


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


def journal(since, *units):
    words = ["journalctl", "-q", "--no-pager", "-o", "cat", "--since", f"@{int(since)}"]
    for unit in units:
        words += ["-u", unit]
    return command(*words, check=False).splitlines()


def wait_for(condition, seconds):
    end = time.time() + seconds
    while time.time() < end:
        if condition():
            return True
        time.sleep(0.5)
    return condition()


def after_retract(result):
    """The daemon deploys the area (a hard floor above what is available), then, back on the real thresholds with a
    quiet window of 20 s, retracts it unused."""
    area = cushion_area()
    if not area:
        raise Mismatch("No Cushion Swap File area to deploy and retract")
    original = SETTINGS.read_text() if SETTINGS.exists() else None
    since = time.time()
    try:
        SETTINGS.write_text((original or "") + "\nDEPLOY_HARD_MIB=1048576\nQUIET_SECONDS=20\n")
        command("systemctl", "restart", "cushion-swap.service")
        deployed = wait_for(lambda: any(entry["name"] == area for entry in swaps()), 20)
        used_while_on = next((entry["used_kib"] for entry in swaps() if entry["name"] == area), None)
        SETTINGS.write_text((original or "") + "\nQUIET_SECONDS=20\n")
        command("systemctl", "restart", "cushion-swap.service")
        retracted = wait_for(lambda: not any(entry["name"] == area for entry in swaps()), 90)
    finally:
        if original is None:
            SETTINGS.unlink(missing_ok=True)
        else:
            SETTINGS.write_text(original)
        command("systemctl", "restart", "cushion-swap.service")
    lines = journal(since, "cushion-swap.service")
    log = [line for line in LOG_FILE.read_text(errors="replace").splitlines() if "area_empty=yes" in line and "retract_ok=1" in line]
    result["after_retract"] = {
        "area": area, "deployed_by_daemon": deployed, "used_kib_while_on": used_while_on, "retracted": retracted,
        "journal": [line for line in lines if re.search(r"DEPLOY|RETRACT|ERROR|starting", line)][:20],
        "log_file_retract_lines": log[-2:],
    }
    actions = "\n".join(lines)
    if not (deployed and retracted):
        raise Mismatch(f"The daemon did not deploy and retract the unused area: {result['after_retract']}")
    if not (re.search(r"DEPLOY succeeded", actions) and re.search(r"RETRACT triggered: .* area unused", actions)
            and re.search(r"RETRACT succeeded", actions)):
        raise Mismatch("The journal does not show the DEPLOY and the RETRACT of the unused area")
    if not log:
        raise Mismatch("The log file has no retract-check with area_empty=yes and retract_ok=1")


def configuration(result, args):
    checks = result.setdefault("checks", {})
    memory = meminfo()
    config = resume_config()
    checks["resume_config"] = config
    if config["source"] is None or config["resume"] in (None, "", "none", "auto") or config["noresume"]:
        raise Mismatch(f"No resume device is configured: {config}")
    if args.expect_source == "file" and (config["source"] != str(RESUME_FILE) or config["cmdline_resume"] or config["cmdline_offset"]):
        raise Mismatch(f"Expected the installer's file alone, with no resume= on the kernel command line: {config}")
    if args.expect_source == "cmdline" and config["source"] != "kernel command line":
        raise Mismatch(f"Expected the kernel command line as the source: {config}")
    target = resume_target(config)
    checks["target"] = target
    if target["size_kib"] < memory["MemTotal"]:
        raise Mismatch(f"The area ({target['size_kib']} KiB) is smaller than RAM ({memory['MemTotal']} KiB)")
    if any(entry["name"] == target["target"] for entry in swaps()):
        raise Mismatch("The area is on; it must be off at rest")

    if args.negative:
        Path("/sys/power/resume").write_text("0:0")
        result["negative_injected"] = Path("/sys/power/resume").read_text().strip() == "0:0"
    kernel = {"resume": Path("/sys/power/resume").read_text().strip(), "offset": int(Path("/sys/power/resume_offset").read_text())}
    checks["kernel"] = kernel
    if kernel["resume"] != target["devno"] or kernel["offset"] != config["offset"]:
        raise Mismatch(f"The kernel resumes from {kernel['resume']} offset {kernel['offset']}, the configured area is "
                       f"{target['devno']} offset {config['offset']}")

    image = Path(f"/boot/initrd.img-{os.uname().release}")
    listing = command("lsinitramfs", str(image)).splitlines() if image.exists() else []
    checks["initramfs"] = {"image": str(image), "resume_script": "usr/share/initramfs-tools/scripts/local-premount/resume" in listing
                           or "scripts/local-premount/resume" in listing,
                           "conf": [line for line in listing if "conf/conf.d" in line]}
    if not checks["initramfs"]["resume_script"] or "conf/conf.d/resume" not in checks["initramfs"]["conf"]:
        raise Mismatch("The initramfs has no resume script or no resume configuration")
    if target["kind"] == "file" and "conf/conf.d/zz-cushion-swap-resume-offset" not in checks["initramfs"]["conf"]:
        raise Mismatch("The initramfs has no resume offset snippet for the swap file")

    package = dict(line.split("=", 1) for line in command("cushion-swap", "--resume-target", check=False).splitlines() if "=" in line)
    checks["package_resume_target"] = package
    if package.get("TARGET") != target["target"] or package.get("SOURCE") != config["source"]:
        raise Mismatch(f"cushion-swap --resume-target says {package}, this probe found {target['target']} from {config['source']}")
    generator = [line for line in command("journalctl", "-b", "-q", "--no-pager", "-o", "short", check=False).splitlines()
                 if "cushion-swap-hibernate-generator" in line]
    checks["generator"] = {"dropin": DROPIN.exists(), "log": generator[-3:]}
    if not DROPIN.exists() or not any(f"Hibernate offered: {config['source']}" in line for line in generator):
        raise Mismatch(f"The generator did not offer Hibernate from {config['source']}: {checks['generator']}")

    unit = "cushion-swap-hibernate.service"
    wants = command("systemctl", "show", "-p", "Wants", "--value", "systemd-hibernate.service", check=False).split()
    checks["hibernate_unit"] = {"enabled": command("systemctl", "is-enabled", unit, check=False), "wanted": unit in wants}
    if checks["hibernate_unit"]["enabled"] != "enabled" or not checks["hibernate_unit"]["wanted"]:
        raise Mismatch(f"{unit} would not switch the area on: {checks['hibernate_unit']}")

    zram = [entry for entry in swaps() if entry["name"].startswith("/dev/zram")]
    checks["zram"] = {"devices": zram}
    if zram and any(entry["priority"] < 0 for entry in zram):
        raise Mismatch("zram must come before the disk swap (a positive priority)")

    if args.negative_dropin:
        NEGATIVE_DROPIN.parent.mkdir(parents=True, exist_ok=True)
        NEGATIVE_DROPIN.write_text("[Service]\nEnvironment=SYSTEMD_BYPASS_HIBERNATION_MEMORY_CHECK=0\n")
        command("systemctl", "daemon-reload")
        command("systemctl", "restart", "systemd-logind.service")
        time.sleep(3)
        result["negative_injected"] = True
    checks["can_hibernate"] = {"root": can_hibernate(), "session_user": can_hibernate(result.get("user")),
                               "kde": kde_can_hibernate(result.get("user"))}
    if checks["can_hibernate"]["root"] != "yes" or checks["can_hibernate"]["session_user"] not in ("yes", "challenge"):
        raise Mismatch(f"logind does not offer Hibernate: {checks['can_hibernate']}")
    if checks["can_hibernate"]["kde"] != "true":
        raise Mismatch(f"KDE (PowerDevil) does not offer Hibernate: {checks['can_hibernate']}")


def negative_switch_on(result):
    """Without cushion-swap-hibernate.service, hibernation must fail: systemd-sleep finds no active area."""
    since = time.time()
    command("systemctl", "mask", "--runtime", "cushion-swap-hibernate.service")
    result["negative_injected"] = True
    try:
        command("systemctl", "hibernate", check=False)
        failed = wait_for(lambda: any("Failed to find location to hibernate to" in line
                                      for line in journal(since, "systemd-hibernate.service")), 60)
        result["negative_journal"] = [line for line in journal(since) if re.search(r"hibernat|sleep|cushion", line, re.I)][:20]
    finally:
        command("systemctl", "unmask", "--runtime", "cushion-swap-hibernate.service", check=False)
    if failed:
        raise Mismatch("Hibernation failed without the switch-on: systemd-sleep found no active area")
    raise RuntimeError("Hibernation did not fail without the switch-on")


def arm(args, result):
    sessions = [line.split() for line in command("loginctl", "list-sessions", "--no-legend").splitlines()]
    seat = [fields for fields in sessions if len(fields) > 3 and fields[3] == "seat0"]
    result["user"] = seat[0][2] if seat else None
    result["secure_boot"] = secure_boot()
    result["cmdline"] = Path("/proc/cmdline").read_text().strip()
    if args.after_retract:
        after_retract(result)
    try:
        configuration(result, args)
    finally:
        if args.negative and result.get("negative_injected"):
            # resume_offset was left as it was; the device written back restores the kernel's setting
            Path("/sys/power/resume").write_text(result["checks"]["target"]["devno"])
        if args.negative_dropin and NEGATIVE_DROPIN.exists():
            NEGATIVE_DROPIN.unlink(missing_ok=True)
            command("systemctl", "daemon-reload")
            command("systemctl", "restart", "systemd-logind.service")
    if args.negative or args.negative_dropin:
        raise RuntimeError("The planted break was not detected")
    if args.negative_switch_on:
        negative_switch_on(result)
    token = secrets.token_hex(16)
    TOKEN.write_text(token)
    # A process in its own unit, so it outlives this one: it must still be there after the resume.
    command("systemd-run", "--unit=sparky-hibernate-witness", "--collect", "--property=Type=exec", "sleep", "infinity")
    witness_pid = int(command("systemctl", "show", "-p", "MainPID", "--value", "sparky-hibernate-witness.service"))
    state = {"boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(), "token": token,
             "witness_pid": witness_pid, "armed_at": time.time(), "uptime": float(Path("/proc/uptime").read_text().split()[0]),
             "target": result["checks"]["target"]["target"]}
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
    wait_for(lambda: not Path("/run/cushion-swap/hibernate-deployed").exists(), 30)
    lines = journal(state["armed_at"])
    target = state["target"]
    result["resume"] = {
        "boot_id_unchanged": boot_id == state["boot_id"],
        "token_in_ram": token == state["token"],
        "witness_alive": witness_alive,
        "journal": [line for line in lines if re.search(r"hibernat|PM: |resume|Cushion Swap File|cushion-swap|S4", line, re.I)][:40],
        "swaps_after": swaps(),
        "can_hibernate_after": can_hibernate(),
        "cmdline": Path("/proc/cmdline").read_text().strip(),
        "secure_boot": secure_boot(),
    }
    command("systemctl", "stop", "sparky-hibernate-witness.service", check=False)
    STATE.unlink()
    TOKEN.unlink(missing_ok=True)
    if not (result["resume"]["boot_id_unchanged"] and result["resume"]["token_in_ram"] and witness_alive):
        raise Mismatch("The machine did not resume from hibernation: this is a fresh boot")
    text = "\n".join(lines)
    if f"hibernation: {target} switched on for the image" not in text:
        raise Mismatch(f"The journal does not show {target} switched on for the image")
    if f"after resume: {target} was empty, switched off again" not in text:
        raise Mismatch(f"The journal does not show {target} switched off again after resume")
    if any(entry["name"] == target for entry in swaps()):
        raise Mismatch(f"{target} is still on after resume")
    if result["resume"]["can_hibernate_after"] != "yes":
        raise Mismatch("logind no longer offers Hibernate after resume")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("phase", choices=("arm", "verify"))
    parser.add_argument("output", type=Path)
    parser.add_argument("--expect-source", choices=("file", "cmdline"))
    parser.add_argument("--after-retract", action="store_true")
    parser.add_argument("--no-hibernate", action="store_true")
    faults = parser.add_mutually_exclusive_group()
    faults.add_argument("--negative", action="store_true")
    faults.add_argument("--negative-dropin", action="store_true")
    faults.add_argument("--negative-switch-on", action="store_true")
    args = parser.parse_args()
    result = {"phase": args.phase, "negative": args.negative or args.negative_dropin or args.negative_switch_on,
              "options": {key: value for key, value in vars(args).items() if key not in ("phase", "output")},
              "failure": None, "verified": False}
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
    args.output.write_text(json.dumps(result, indent=2, default=str) + "\n")
    os.sync()
    return status


if __name__ == "__main__":
    sys.exit(main())
