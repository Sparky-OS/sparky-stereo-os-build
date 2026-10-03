#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/03
"""Turn captured hardware facts into a deterministic installation plan."""
import pathlib
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
    else:
        emit("found", "NVIDIA nouveau: older, unknown, mixed or non-amd64 hardware")
else:
    emit("found", "No NVIDIA display controller")

xbox_usb = {"028e", "028f", "02d1", "02dd", "02e3", "02ea", "0b00", "0b0a", "0b12"}
xbox_bt = {"02e0", "02fd", "0b05", "0b13", "0b20", "0b22"}
pad = "ID_INPUT_JOYSTICK=1" in read("input-properties")
for vendor, product in re.findall(r"\bID ([0-9a-fA-F]{4}):([0-9a-fA-F]{4})\b", read("lsusb")):
    vendor, product = vendor.lower(), product.lower()
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
for package in sorted(packages):
    emit("package", package)
