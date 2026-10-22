#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10
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
        if vendor == "GenuineIntel" and laptop == "0":
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

if gpus:
    match("NVIDIA display " + ", ".join(gpu[0] for gpu in gpus), "firmware-nvidia-graphics")
    supported = {tuple(line.split()) for line in (data / "nvidia-open.ids").read_text().splitlines()}
    if all((gpu[0],) in supported or tuple(gpu) in supported for gpu in gpus) and read("architecture").strip() == "amd64":
        emit("action", "nvidia-open")
        if laptop == "0":
            emit("action", "nvidia-runtime-pm")
    else:
        emit("found", "NVIDIA nouveau: older, unknown, mixed or non-amd64 hardware")
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

# Network PCI IDs (classes 0200 Ethernet, 0280 and 0282 wireless) against share/network-ids.tsv.
network_ids = {}
table = data / "network-ids.tsv"
if new_facts and table.is_file():
    for line in table.read_text().splitlines():
        if line and not line.startswith("#"):
            pci_id, driver, package, note = line.split("\t")
            network_ids[pci_id] = (driver, package, note)
network_seen = []
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
    emit("fact", f"network-driver\t{pci_id} {driver} (in our kernel) {note}")
    if package == "BROADCOM-WL":
        # Daniel, 2026-10-05: Debian's unmodified broadcom-sta-dkms goes on the ISO and is
        # installed only for a matching card, with its licence shown. Here it is only named.
        emit("candidate", f"broadcom-sta-dkms\t{pci_id}: closed Broadcom wl driver (Debian non-free, Broadcom licence); "
                          "a licence must be shown to the user before it is installed; nothing is installed by this tool yet")
    elif package != "-":
        match(f"Network {pci_id} {note}: firmware {package}", package)
if network_seen:
    emit("fact", "network-pci\t" + " ".join(sorted(set(network_seen))))

for package in sorted(packages):
    emit("package", package)
