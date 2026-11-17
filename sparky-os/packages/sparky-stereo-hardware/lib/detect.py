#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/16
"""Turn captured hardware facts into a deterministic installation plan."""
import pathlib
import json
import re
import sys

facts, data = map(pathlib.Path, sys.argv[1:3])


def read(name):
    return (facts / name).read_text()


def emit(kind, value):
    print(f"{kind}\t{value}")


packages = set()


def match(reason, *names):
    emit("found", reason)
    packages.update(names)


laptop = read("laptop").strip()
if laptop == "0":
    match("Laptop (laptop-detect)", "task-laptop", "power-profiles-daemon")
elif laptop == "1":
    emit("found", "Desktop (laptop-detect)")
else:
    raise SystemExit("Invalid laptop-detect result")

vendors = set(re.findall(r"^vendor_id\s*:\s*(\S+)", read("cpuinfo"), re.M))
for vendor, package in (("AuthenticAMD", "amd64-microcode"), ("GenuineIntel", "intel-microcode")):
    if vendor in vendors:
        match(f"CPU {vendor}", package)
        if vendor == "GenuineIntel":
            # thermald exits on any other vendor ("Unsupported cpu model or platform"), so only an Intel machine gets it
            packages.add("thermald")
if not vendors:
    emit("found", "No x86 CPU vendor")

for package in read("firmware-packages").split():
    if not re.fullmatch(r"[a-z0-9][a-z0-9+.-]+", package):
        raise SystemExit("Invalid isenkram package name")
    match(f"isenkram missing firmware: {package}", package)

gpus = []
amd_display = False
current_gpu = None
for line in read("lspci").splitlines():
    subsystem = re.search(r"Subsystem:.*?([0-9a-fA-F]{4}):([0-9a-fA-F]{4})", line)
    if subsystem and current_gpu is not None:
        gpus[current_gpu].extend(part.lower() for part in subsystem.groups())
    if line and not line[0].isspace():
        current_gpu = None
    # lspci -Dnnv includes subsystem restrictions from NVIDIA's support table.
    pci = re.search(r"(?:\[)?([0-9a-fA-F]{4})(?:\])?: .*?(?:\[)?([0-9a-fA-F]{4}):([0-9a-fA-F]{4})(?:\])?", line)
    if not pci:
        continue
    cls, vendor, device = (part.lower() for part in pci.groups())
    if vendor == "1002" and cls.startswith("03"):
        amd_display = True
    if vendor == "10de" and cls.startswith("03"):
        current_gpu = len(gpus)
        gpus.append([device])
    if vendor == "1102" and device in {"0010", "0011", "0012"}:
        match(f"Creative CA0132 {vendor}:{device}", "firmware-creative-stereo")
        emit("action", "creative-msi")

def nvidia_table(name):
    return {tuple(line.split()) for line in (data / name).read_text().splitlines()}


def listed(gpu, table):
    """NVIDIA's README tables: a row with a subsystem matches only that subsystem."""
    return (gpu[0],) in table or tuple(gpu) in table


if gpus:
    match("NVIDIA display " + ", ".join(gpu[0] for gpu in gpus), "firmware-nvidia-graphics")
    supported = nvidia_table("nvidia-open.ids")
    # NVIDIA's 580 branch, the last for Maxwell, Pascal and Volta (the "legacy_580.xx" table of NVIDIA's 615.71.09 README):
    # the edition builds its kernel modules (nvidia-legacy-580xx-kernel-dkms) for the cards the open modules do not run.
    legacy = nvidia_table("nvidia-legacy-580xx.ids")
    amd64 = read("architecture").strip() == "amd64"
    if all(listed(gpu, supported) for gpu in gpus) and amd64:
        emit("action", "nvidia-open")
        if laptop == "0":
            emit("action", "nvidia-runtime-pm")
    elif all(listed(gpu, legacy) for gpu in gpus) and amd64:
        # Two drivers give these cards different results, so both are the person's choice (Daniel, 2026-10-14: "where two
        # paths appear differ, make sure it's a user option then and do both"). NVIDIA's runtime power management needs a
        # Turing card or newer (NVIDIA's 580.196.07 README, Dynamic Power Management), so no RTD3 action here.
        emit("action", "nvidia-legacy-580xx")
        emit("found", "NVIDIA " + ", ".join(gpu[0] for gpu in gpus) + ": a Maxwell, Pascal or Volta card, which the edition's "
             "open modules with HDMI 3D (Turing and newer) do not run; NVIDIA's 580 driver, the last for these cards, runs it")
        emit("choice", "nvidia-580\tdefault: NVIDIA's 580 driver: full clocks, hardware video decoding (NVDEC), CUDA 12; "
             "NVIDIA's display code is closed, so no HDMI 3D modes (the television does not switch itself, no frame packing); "
             "Stereo KWin's anaglyph, interleaved, side by side and top and bottom for a screen switched by hand, and output "
             "pairs work")
        emit("choice", "nouveau\tthe edition's HDMI 3D modes (the television switches itself into 3D, frame packing), at the "
             "card's boot clocks (nouveau does not reclock Pascal and Volta), without hardware video decoding")
    else:
        older = {}
        for line in (data / "nvidia-legacy-older.tsv").read_text().splitlines():
            device, branch = line.split("\t")
            older[device] = branch
        reasons = []
        for gpu in gpus:
            if listed(gpu, supported):
                reasons.append(f"{gpu[0]} runs on the edition's open modules")
            elif listed(gpu, legacy):
                reasons.append(f"{gpu[0]} runs on NVIDIA's 580 driver")
            elif gpu[0] in older:
                reasons.append(f"{gpu[0]}: NVIDIA's last driver for it is its legacy {older[gpu[0]]} branch, which the "
                               "edition does not build")
            else:
                reasons.append(f"{gpu[0]} is in none of NVIDIA's 615.71.09 tables")
        emit("found", "NVIDIA " + ", ".join(gpu[0] for gpu in gpus) + ": not supported by the edition's NVIDIA driver with "
             "HDMI 3D, which needs a Turing card or newer for every NVIDIA card of the machine, on amd64; nothing is installed "
             "for it, and the card keeps nouveau")
        if amd64:
            emit("found", "NVIDIA cards: " + "; ".join(reasons) + "; one NVIDIA driver runs all the cards of a machine, so "
                 "they keep nouveau")
else:
    emit("found", "No NVIDIA display controller")

# PPD 0.30 probes its AMD actions by CPU vendor, not by the Radeon PCI ID alone.
if amd_display and "AuthenticAMD" in vendors:
    packages.add("power-profiles-daemon")
    emit("action", "amdgpu-dpm")
    if laptop == "0":
        emit("action", "amdgpu-panel")

xbox_usb = {"028e", "028f", "02d1", "02dd", "02e3", "02ea", "0b00", "0b0a", "0b12"}
xbox_bt = {"02e0", "02fd", "0b05", "0b13", "0b20", "0b22"}
rigs = json.loads((data / "rig-devices.json").read_text())
rig_ids = {(row["vendor"], row["product"]): row for row in rigs}
pad = "ID_INPUT_JOYSTICK=1" in read("input-properties")
for vendor, product in re.findall(r"\bID ([0-9a-fA-F]{4}):([0-9a-fA-F]{4})\b", read("lsusb")):
    vendor, product = vendor.lower(), product.lower()
    if (vendor, product) in rig_ids:
        rig = rig_ids[vendor, product]
        match(f"{rig['name']} {vendor}:{product}", "sparky-sim-hidraw")
        if rig.get("driver"):
            if rig["policy"] == "stable":
                packages.add(rig["driver"])
            else:
                emit("candidate", f"{rig['driver']}\t{vendor}:{product}: {rig['policy']}; keep the current driver until selected")
    if vendor == "17e9":
        match(f"DisplayLink USB {vendor}:{product}", "evdi-dkms")
    if vendor == "045e" and product in xbox_usb:
        match(f"Xbox USB {vendor}:{product}; xpadneo available for Bluetooth pairing", "xpadneo-dkms")
        pad = True
    if (vendor, product) in {("054c", "05c4"), ("054c", "09cc"), ("054c", "0ce6"), ("057e", "2009")}:
        pad = True
for bus, vendor, product in re.findall(r"HID_ID=([0-9A-Fa-f]+):([0-9A-Fa-f]+):([0-9A-Fa-f]+)", read("hid-uevents")):
    if int(bus, 16) == 5 and ((int(vendor, 16) == 0x045e and f"{int(product, 16):04x}" in xbox_bt)
                            or (int(vendor, 16), int(product, 16)) == (0x0b05, 0x1abd)):
        match(f"xpadneo Bluetooth HID {vendor}:{product}", "xpadneo-dkms")
        pad = True
if pad:
    match("Game controller", "steam-devices")
else:
    emit("found", "No game controller")


def read_optional(name):
    """Facts added in 2026-10: a fixture or an older caller may not have them."""
    path = facts / name
    return path.read_text() if path.is_file() else None


# CPU level. The loader's own list decides (the lines of `ld.so --help` marked
# "supported, searched", the same test CachyOS's cachyos-repo.sh makes, read from
# https://mirror.cachyos.org/cachyos-repo.tar.xz on 2026-10-05); the flags of /proc/cpuinfo are
# checked against the x86-64 psABI level definitions (the flag lists as apt-3.3.3 test/integration/varianttable
# writes them, read 2026-10-05) and a disagreement is printed, never hidden.
LEVEL_FLAGS = {
    2: {"cx16", "lahf_lm", "popcnt", "sse4_1", "sse4_2", "ssse3"},
    3: {"avx", "avx2", "bmi1", "bmi2", "f16c", "fma", "abm", "movbe", "xsave"},
    4: {"avx512f", "avx512bw", "avx512cd", "avx512dq", "avx512vl"},
}
ldso = read_optional("ldso-help")
new_facts = ldso is not None   # a caller that predates these facts gets the old output only
if new_facts:
    loader_level = 1
    for level in (2, 3, 4):
        if re.search(rf"^\s*x86-64-v{level} \(supported, searched\)", ldso, re.M):
            loader_level = level
    flags = set()
    for line in read("cpuinfo").splitlines():
        if line.startswith("flags"):
            flags = set(line.split(":", 1)[1].split())
            break
    flag_level = 1
    for level in (2, 3, 4):
        if LEVEL_FLAGS[level] <= flags:
            flag_level = level
        else:
            break
    emit("fact", f"cpu-level\tv{loader_level}")
    emit("fact", f"x86-64-v3\t{'yes' if loader_level >= 3 else 'no'}")
    # The kernel built for the processor's level (ORDER 108; Daniel, 2026-10-05: "no optional, v3", automatic, "The baseline must
    # always stay installed and bootable; optimised parts only add to it"). linux-image-sparky-stereo stays (the ISO installs it and
    # nothing here removes it), so GRUB lists both; the v3 release sorts above the base release of the same build, so it boots first
    # (tests/kernel-v3.sh). The person's own choice, --kernel base, is kept for the machine (the fact file kernel-choice).
    if loader_level >= 3 and read("architecture").strip() == "amd64":
        choice = (read_optional("kernel-choice") or "").strip()
        if choice == "base":
            emit("found", "x86-64-v3 processor: the baseline kernel was chosen for this machine (sparky-stereo-hardware --kernel v3 undoes it)")
        else:
            match("x86-64-v3 processor: the kernel built for x86-64-v3 (the baseline kernel stays installed and in GRUB)",
                  "linux-image-sparky-stereo-v3", "linux-headers-sparky-stereo-v3")
    if flag_level != loader_level:
        emit("fact", f"cpu-level-disagreement\tloader v{loader_level}, cpuinfo flags v{flag_level}; the loader's answer is used")

# Board: DMI vendor and name (/sys/class/dmi/id/board_vendor and board_name; the keys the
# OpenRGB project's documentation uses to recognise boards, e.g. Gigabyte).
board_vendor = read_optional("dmi-board-vendor")
board_name = read_optional("dmi-board-name")
if board_vendor is not None or board_name is not None:
    emit("fact", "board\t" + " / ".join(x.strip() for x in (board_vendor or "?", board_name or "?")))

# USB vendor IDs present. Names only for RGB and peripheral makers, taken from the OpenRGB
# project's udev rules documentation (read 2026-10-05). Nothing is installed for them.
USB_VENDOR_NAMES = {"1b1c": "Corsair", "1532": "Razer", "046d": "Logitech", "0b05": "ASUS",
                    "1038": "SteelSeries", "1e71": "NZXT", "1462": "MSI", "1044": "Gigabyte"}
usb_vendors = sorted({vendor.lower() for vendor, _ in re.findall(r"\bID ([0-9a-fA-F]{4}):([0-9a-fA-F]{4})\b", read("lsusb"))})
if usb_vendors and new_facts:
    emit("fact", "usb-vendors\t" + " ".join(v + (f" ({USB_VENDOR_NAMES[v]})" if v in USB_VENDOR_NAMES else "") for v in usb_vendors))

# Lights and peripherals (ORDER 108, milestone 6). A device seen on USB leads to its tool, installed without a question, from the
# tool's own list of the devices it drives (share/peripherals/*.ids, made by tools/make-peripheral-ids.py from the package's udev
# rules or device files; the first lines of each say which package and version). One owner per device: where OpenLinkHub is
# installed (the `openlinkhub` fact) and a device is one it opens too (share/peripherals/owners.tsv), the tools it keeps out are
# not installed for that device, and the udev rule 62-sparky-stereo-peripheral-owner.rules takes their access away. The image
# already carries OpenRGB; the plan names it so a machine that lost it gets it back.
def device_table(name):
    table = {}
    path = data / "peripherals" / name
    if path.is_file():
        for line in path.read_text().splitlines():
            if line and not line.startswith("#"):
                ident, _, label = line.partition("\t")
                table[ident] = label.split("\t")[0] if name != "owners.tsv" else line
    return table


usb_ids = sorted({f"{v.lower()}:{p.lower()}" for v, p in re.findall(r"\bID ([0-9a-fA-F]{4}):([0-9a-fA-F]{4})\b", read("lsusb"))})
olh_installed = (read_optional("openlinkhub") or "").strip() == "yes"
owned = {}
for ident, row in device_table("owners.tsv").items():
    _, owner, kept_out, label = (row.split("\t") + [""] * 4)[:4]
    owned[ident] = (owner, set(kept_out.split(",")), label)
openrgb_devices = []
for tool, name, tool_packages in (("openrgb", "OpenRGB", ("openrgb",)), ("solaar", "Solaar", ("solaar",)),
                                  ("ratbag", "libratbag with Piper", ("ratbagd", "piper")), ("liquidctl", "liquidctl", ("liquidctl",)),
                                  ("g810-led", "g810-led", ("g810-led",)), ("openrazer", "OpenRazer", ("openrazer-daemon", "openrazer-driver-dkms"))):
    table = device_table(tool + ".ids")
    seen = []
    for ident in usb_ids:
        if ident not in table:
            continue
        if olh_installed and ident in owned and tool in owned[ident][1]:
            emit("owner", f"{ident}\t{owned[ident][0]}\tnot {name}\t{owned[ident][2] or table[ident] or ident}")
            continue
        seen.append(ident)
    if seen:
        match(f"{name} drives {', '.join(seen)}", *tool_packages)
        emit("fact", f"peripheral\t{tool}\t{' '.join(seen)}")
        if tool == "openrgb":
            openrgb_devices = seen
# Motherboard and memory lights over the SMBus cannot be seen from USB: a desktop whose board maker is one OpenRGB's detectors
# name (its sources check "Micro-Star International Co., Ltd." and "Gigabyte Technology Co., Ltd."; ASUS Aura, ASRock Polychrome and EVGA
# are found by probing the bus) gets the modules that make the bus reachable (i2c-dev and the chipset's driver, OpenRGB's SMBusAccess.md) and
# the tools to look at it (i2c-tools). Without RGB memory or a board of that generation the document says to skip all of it: the board maker is the
# nearest thing a machine shows without probing the bus.
SMBUS_BOARD_MAKERS = ("asustek", "gigabyte", "micro-star", "asrock", "evga", "biostar")
board_maker = (board_vendor or "").strip().lower()
if laptop == "1" and any(board_maker.startswith(maker) for maker in SMBUS_BOARD_MAKERS):
    match(f"Desktop board {board_vendor.strip()}: the SMBus for OpenRGB (i2c-dev, i2c-tools)", "i2c-tools", "openrgb")
    # OpenRGB's own SMBusAccess.md (in its package): i2c-tools, the i2c-dev module, and the chipset's driver (i2c-i801 on Intel, i2c-piix4 on AMD)
    smbus = ["i2c-dev"] + (["i2c-i801"] if "GenuineIntel" in vendors else ["i2c-piix4"] if "AuthenticAMD" in vendors else [])
    emit("action", "i2c-dev")
    emit("fact", "smbus-modules\t" + " ".join(smbus))
    emit("fact", "peripheral\tsmbus\t" + board_vendor.strip())
    openrgb_devices = openrgb_devices or ["smbus"]
if openrgb_devices:
    emit("action", "openrgb-session")

# Network PCI IDs (classes 0200 Ethernet, 0280 and 0282 wireless) against share/network-ids.tsv.
network_ids = {}
table = data / "network-ids.tsv"
if new_facts and table.is_file():
    for line in table.read_text().splitlines():
        if line and not line.startswith("#"):
            pci_id, driver, package, note = line.split("\t")
            network_ids[pci_id] = (driver, package, note)
network_seen = []
actions = []
for line in read("lspci").splitlines() if new_facts else []:
    if not line or line[0].isspace():
        continue
    pci = re.search(r"\[?([0-9a-fA-F]{4})\]?: .*?\[?([0-9a-fA-F]{4}):([0-9a-fA-F]{4})\]?", line)
    if not pci or pci.group(1).lower() not in {"0200", "0280", "0282"}:
        continue
    pci_id = f"{pci.group(2)}:{pci.group(3)}".lower()
    network_seen.append(pci_id)
    # Intel and Qualcomm Atheros Wi-Fi: every ID of the vendor needs the vendor's firmware package
    # (iwlwifi has 453 aliases and ath10k/11k/12k many in our kernel's modules.alias), so by vendor.
    driver, package, note = network_ids.get(pci_id, (None, None, None))
    if driver is None and pci.group(1).lower() in {"0280", "0282"}:
        vendor = pci.group(2).lower()
        driver, package, note = {"8086": ("iwlwifi", "firmware-iwlwifi", "Intel Wi-Fi"),
                                 "168c": ("ath9k/ath10k", "firmware-atheros", "Qualcomm Atheros Wi-Fi"),
                                 "17cb": ("ath11k/ath12k", "firmware-atheros", "Qualcomm Atheros Wi-Fi")}.get(vendor, (None, None, None))
    if driver is None:
        continue
    # "wl" in the driver column: no driver of our kernel drives this chip (BCM4360, BCM4352), so it is not "in our kernel"
    emit("fact", f"network-driver\t{pci_id} {driver}{'' if driver.startswith('wl') else ' (in our kernel)'} {note}")
    if package == "BROADCOM-WL":
        # Daniel, 2026-10-05: Debian's unmodified broadcom-sta-dkms goes on the ISO and is
        # installed only for a matching card, with its licence shown. This tool only plans: the
        # candidate line stays, and a licence line names the file the action layer must show first
        # (the package's own copyright file, Broadcom's Software License Agreement) and the card that needs it.
        emit("candidate", f"broadcom-sta-dkms\t{pci_id}: closed Broadcom wl driver (Debian non-free, Broadcom licence); "
                          "a licence must be shown to the user before it is installed; it is installed only when the person says yes after reading it")
        emit("licence", f"broadcom-sta-dkms\t{pci_id}\tBroadcom Software License Agreement\tusr/share/doc/broadcom-sta-dkms/copyright")
        if driver.startswith("wl"):
            emit("fact", f"network-no-kernel-driver\t{pci_id}")
            # a card no driver of our kernel drives: the action layer offers wl for it (the licence first, the person's yes
            # after); the plan installs nothing itself, so no "package" line names broadcom-sta-dkms
            if "broadcom-wl" not in actions:
                actions.append("broadcom-wl")
                emit("action", "broadcom-wl")
    elif package != "-":
        match(f"Network {pci_id} {note}: firmware {package}", package)
if network_seen:
    emit("fact", "network-pci\t" + " ".join(sorted(set(network_seen))))

for package in sorted(packages):
    emit("package", package)
