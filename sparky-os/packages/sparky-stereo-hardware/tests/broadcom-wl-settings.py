#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/24 (row 728b)
# Copyright 2026 under the GNU GPL3 License
"""The NetworkManager settings for the cards Broadcom's wl can drive (bin/sparky-stereo-broadcom-wl-settings), against a
sysfs tree made here: a BCM4331 (14e4:4331, a BROADCOM-WL row) under b43 then wl then b43 again, a BCM4318 (14e4:4318, which
only b43 drives) and an Intel card beside it; the card leaving; the person's file in /etc; a file of the same name that is
not ours; an interface with no permanent address; NetworkManager stopped, missing or refusing to reload. systemctl, nmcli
and sparky-stereo-problems are doubles that write what they were asked. Run in a container: python3 broadcom-wl-settings.py"""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

recipe = pathlib.Path(__file__).resolve().parent.parent
tool = recipe / "bin/sparky-stereo-broadcom-wl-settings"
fails = 0


def check(what, ok, detail=""):
    global fails
    print(("PASS " if ok else "FAIL ") + what + ("" if ok else f" ({detail})"))
    fails += 0 if ok else 1


class Machine:
    def __init__(self, root):
        self.root = pathlib.Path(root)
        self.sys = self.root / "sys"
        self.perm = self.root / "perm"
        self.calls = self.root / "calls"
        self.bin = self.root / "bin"
        self.nm_state = self.root / "nm-state"
        for d in ("sys/bus/pci/devices", "sys/class/net", "sys/bus/bcma/drivers/b43", "sys/bus/pci/drivers/wl",
                  "sys/bus/pci/drivers/iwlwifi", "usr/sbin", "etc/NetworkManager/conf.d", "problems", "bin"):
            (self.root / d).mkdir(parents=True, exist_ok=True)
        (self.root / "usr/sbin/NetworkManager").write_text("")
        self.perm.write_text("")
        self.calls.write_text("")
        self.nm_state.write_text("active\n")
        self.double("systemctl", f'echo "systemctl $*" >>{self.calls}; cat {self.nm_state}')
        self.double("nmcli", f'echo "nmcli $*" >>{self.calls}; [ ! -e {self.root}/nmcli-fails ] || {{ echo "Error: reload refused" >&2; exit 1; }}')
        self.double("sparky-stereo-problems", f'echo "problems $*" >>{self.calls}')

    def double(self, name, body):
        p = self.bin / name
        p.write_text(f"#!/bin/sh\n{body}\n")
        p.chmod(0o755)

    def card(self, address, vendor, device):
        dev = self.sys / f"devices/pci0000:00/0000:00:1c.1/{address}"
        dev.mkdir(parents=True, exist_ok=True)
        (dev / "vendor").write_text(f"0x{vendor}\n")
        (dev / "device").write_text(f"0x{device}\n")
        link = self.sys / "bus/pci/devices" / address
        if not link.is_symlink():
            link.symlink_to(os.path.relpath(dev, link.parent))
        return dev

    def remove_card(self, address):
        (self.sys / "bus/pci/devices" / address).unlink()
        shutil.rmtree(self.sys / f"devices/pci0000:00/0000:00:1c.1/{address}")

    def iface(self, name, device, driver, perm, wireless=True):
        """an interface whose device is DEVICE (a card or a device under it), bound to DRIVER"""
        device.mkdir(parents=True, exist_ok=True)
        drivers = {"b43": "bus/bcma/drivers/b43", "wl": "bus/pci/drivers/wl", "iwlwifi": "bus/pci/drivers/iwlwifi"}
        drv = device / "driver"
        if drv.is_symlink():
            drv.unlink()
        drv.symlink_to(os.path.relpath(self.sys / drivers[driver], device))
        net = self.sys / "class/net" / name
        net.mkdir(parents=True)
        if wireless:
            (net / "wireless").mkdir()
        (net / "device").symlink_to(os.path.relpath(device, net))
        if perm:
            with self.perm.open("a") as f:
                f.write(f"{name}\t{perm}\n")

    def remove_iface(self, name):
        shutil.rmtree(self.sys / "class/net" / name)
        self.perm.write_text("".join(l for l in self.perm.read_text().splitlines(True) if not l.startswith(name + "\t")))

    def run(self, *args):
        self.calls.write_text("")
        env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}", SPARKY_STEREO_SYSFS=str(self.sys),
                   SPARKY_STEREO_HARDWARE_DATA=str(recipe / "share"),
                   SPARKY_STEREO_HARDWARE_STATE=str(self.root / "var/lib/sparky-stereo-hardware"),
                   SPARKY_STEREO_NM_RUN_CONF=str(self.root / "run/NetworkManager/conf.d"),
                   SPARKY_STEREO_NM_ETC_CONF=str(self.root / "etc/NetworkManager/conf.d"),
                   SPARKY_STEREO_NETWORKMANAGER=str(self.root / "usr/sbin/NetworkManager"),
                   SPARKY_STEREO_PERM_ADDRESSES=str(self.perm), SPARKY_STEREO_PROBLEMS_STORE=str(self.root / "problems"))
        done = subprocess.run([sys.executable, str(tool), *args], env=env, capture_output=True, text=True)
        self.out = done.stdout + done.stderr
        return done.returncode

    @property
    def conf_path(self):
        return self.root / "run/NetworkManager/conf.d/sparky-stereo-broadcom-wl.conf"

    def conf(self):
        return self.conf_path.read_text() if self.conf_path.exists() else None

    def specs(self):
        text = self.conf() or ""
        return [l.split("=", 1)[1] for l in text.splitlines() if l.startswith("match-device=")]

    def record(self):
        p = self.root / "var/lib/sparky-stereo-hardware/broadcom-wl-cards"
        return p.read_text() if p.exists() else ""

    def calls_text(self):
        return self.calls.read_text()


A_B43, A_WL, OTHER, INTEL = "00:25:00:aa:bb:01", "00:25:00:aa:bb:02", "00:11:22:33:44:55", "a0:88:b4:00:00:01"
with tempfile.TemporaryDirectory() as work:
    m = Machine(work)
    mac = m.card("0000:03:00.0", "14e4", "4331")
    m.iface("wlp3s0b1", mac / "bcma0:1", "b43", A_B43)

    print("== a BCM4331 under b43, NetworkManager running")
    rc = m.run("write", "--reload")
    check("exit 0", rc == 0, m.out)
    check("both sections matched on the card's permanent address under b43",
          m.specs() == [f"mac:{A_B43}", f"mac:{A_B43}"], m.specs())
    text = m.conf() or ""
    check("power saving off, no address change while scanning, the permanent address",
          "\nwifi.powersave=2\n" in text and "\nwifi.scan-rand-mac-address=no\n" in text and "\nwifi.cloned-mac-address=permanent\n" in text)
    check("no section names a driver or an interface", "driver:" not in "".join(m.specs()) and "interface-name:" not in "".join(m.specs()))
    check("its first line marks it as written by the package", text.startswith("# Written by sparky-stereo-hardware (broadcom-wl-settings)"))
    check("the record keeps the card, its id, the address and the driver",
          m.record().startswith(f"0000:03:00.0\t14e4:4331\t{A_B43}\tb43\t"), m.record())
    check("NetworkManager reads its files again", "nmcli general reload conf" in m.calls_text(), m.calls_text())
    check("nothing kept, nothing cleared (nothing was kept)", "problems" not in m.calls_text(), m.calls_text())

    print("== the same again: nothing changes")
    before = m.conf()
    rc = m.run("write", "--reload")
    check("exit 0, the same file", rc == 0 and m.conf() == before)
    check("no reload when nothing changed", "nmcli" not in m.calls_text(), m.calls_text())

    print("== the swap: wl has the card, on the PCI device, another name and another permanent address")
    m.remove_iface("wlp3s0b1")
    m.iface("wlp3s0", mac, "wl", A_WL)
    rc = m.run("write", "--reload")
    check("exit 0", rc == 0, m.out)
    check("both addresses match: the one under b43 and the one under wl",
          m.specs() == [f"mac:{A_B43},mac:{A_WL}"] * 2, m.specs())
    check("the record names wl for the new address", f"{A_WL}\twl\t" in m.record(), m.record())
    check("NetworkManager reads its files again", "nmcli general reload conf" in m.calls_text())

    print("== the way back: b43 again, its address already in the file")
    m.remove_iface("wlp3s0")
    m.iface("wlp3s0b1", mac / "bcma0:1", "b43", A_B43)
    before = m.conf()
    rc = m.run("write", "--reload")
    check("exit 0, the file unchanged, no reload", rc == 0 and m.conf() == before and "nmcli" not in m.calls_text())

    print("== the same address under both drivers is one row with both drivers")
    m2 = Machine(pathlib.Path(work) / "same")
    d = m2.card("0000:03:00.0", "14e4", "4331")
    m2.iface("wlp3s0b1", d / "bcma0:1", "b43", A_B43)
    m2.run("write")
    m2.remove_iface("wlp3s0b1")
    m2.iface("wlp3s0", d, "wl", A_B43)
    m2.run("write")
    check("one address, seen under b43 and wl", m2.specs() == [f"mac:{A_B43}"] * 2 and f"{A_B43}\tb43,wl\t" in m2.record(), m2.record())

    print("== cards that are not BROADCOM-WL rows: a BCM4318 under b43, an Intel card")
    bcm4318 = m.card("0000:04:00.0", "14e4", "4318")
    m.iface("wlp4s0b1", bcm4318 / "ssb0:0", "b43", OTHER)
    intel = m.card("0000:05:00.0", "8086", "24fd")
    m.iface("wlp5s0", intel, "iwlwifi", INTEL)
    rc = m.run("write", "--reload")
    check("exit 0", rc == 0, m.out)
    check("neither address is in the file", OTHER not in (m.conf() or "") and INTEL not in (m.conf() or ""), m.specs())
    check("neither is in the record", OTHER not in m.record() and INTEL not in m.record())

    print("== a wired interface under the card is not a Wi-Fi interface")
    m.iface("enp3s0", mac / "other", "wl", "00:25:00:aa:bb:09", wireless=False)
    m.run("write")
    check("left out", "00:25:00:aa:bb:09" not in (m.conf() or ""))
    m.remove_iface("enp3s0")

    print("== the person's own file of the same name in /etc")
    mine = m.root / "etc/NetworkManager/conf.d/sparky-stereo-broadcom-wl.conf"
    mine.write_text("# mine\n")
    rc = m.run("write", "--reload")
    check("exit 0, ours still written in /run (NetworkManager reads theirs instead)", rc == 0 and m.conf() is not None)
    check("the run says the person's file replaces ours", "is the person's and replaces" in m.out, m.out)
    check("the person's file is untouched", mine.read_text() == "# mine\n")
    mine.unlink()

    print("== a file of our name in /run that we did not write")
    keep = m.conf_path.read_text()
    m.conf_path.write_text("[device-x]\nmatch-device=*\n")
    rc = m.run("write", "--reload")
    check("exit 1", rc == 1, m.out)
    check("left byte for byte", m.conf_path.read_text() == "[device-x]\nmatch-device=*\n")
    check("kept in the engine with LOCAL111 and the repair",
          "problems keep --repair" in m.calls_text() and "broadcom-wl-settings LOCAL111" in m.calls_text(), m.calls_text())
    m.conf_path.write_text(keep)
    (m.root / "problems/sparky-stereo-hardware_broadcom-wl-settings.json").write_text("{}")
    rc = m.run("write", "--reload")
    check("a later run that works clears the kept problem", rc == 0 and "problems clear sparky-stereo-hardware broadcom-wl-settings" in m.calls_text(), m.calls_text())
    (m.root / "problems/sparky-stereo-hardware_broadcom-wl-settings.json").unlink()

    print("== an interface of the card with no permanent address")
    m3 = Machine(pathlib.Path(work) / "noperm")
    d = m3.card("0000:03:00.0", "14e4", "4331")
    m3.iface("wlp3s0", d, "wl", None)
    rc = m3.run("write", "--reload")
    check("exit 1, kept with LOCAL112 naming the card, the interface and the driver",
          rc == 1 and "LOCAL112 14e4:4331 wlp3s0 wl wlp3s0" in m3.calls_text(), m3.calls_text())
    check("no file is written for an address nobody knows", m3.conf() is None)

    print("== NetworkManager stopped, missing, refusing")
    m.nm_state.write_text("inactive\n")
    m.conf_path.unlink()
    rc = m.run("write", "--reload")
    check("stopped: the file is written, NetworkManager is not asked (asking could start it)",
          rc == 0 and m.conf() is not None and "nmcli" not in m.calls_text(), m.calls_text())
    m.nm_state.write_text("active\n")
    (m.root / "nmcli-fails").write_text("")
    m.conf_path.unlink()
    rc = m.run("write", "--reload")
    check("a refused reload: exit 1, kept with LOCAL113 and nmcli's words",
          rc == 1 and "LOCAL113 nmcli general reload conf: exit 1: Error: reload refused" in m.calls_text(), m.calls_text())
    (m.root / "nmcli-fails").unlink()
    rc = m.run("write", "--force-reload")
    check("--force-reload asks even when nothing changed (the upgrade from 0.1.39)", rc == 0 and "nmcli general reload conf" in m.calls_text())
    (m.root / "usr/sbin/NetworkManager").unlink()
    m.conf_path.unlink()
    rc = m.run("write", "--reload")
    check("NetworkManager not installed: nothing written, exit 0", rc == 0 and m.conf() is None and "not installed" in m.out, m.out)
    (m.root / "usr/sbin/NetworkManager").write_text("")

    print("== show writes nothing")
    rc = m.run("show")
    check("show prints the cards and the file, writes none", rc == 0 and "card 0000:03:00.0 14e4:4331" in m.out and m.conf() is None, m.out)

    print("== the card leaves the computer")
    m.run("write", "--reload")
    m.remove_iface("wlp3s0b1")
    m.remove_card("0000:03:00.0")
    rc = m.run("write", "--reload")
    check("exit 0, the file is gone", rc == 0 and m.conf() is None, m.out)
    check("the record no longer has the card", "0000:03:00.0" not in m.record(), m.record())
    check("NetworkManager reads its files again", "nmcli general reload conf" in m.calls_text())
    check("the other cards never had a record", m.record() == "", m.record())

    print("== the table: every id the writer serves is a BROADCOM-WL row")
    rows = [l.split("\t") for l in (recipe / "share/network-ids.tsv").read_text().splitlines() if l and not l.startswith("#")]
    wl = {r[0] for r in rows if r[2] == "BROADCOM-WL"}
    check("21 BROADCOM-WL rows, all vendor 14e4", len(wl) == 21 and all(i.startswith("14e4:") for i in wl), sorted(wl))

print("== the writer's messages in the ten languages, for the person and for the engine")
import re
langs = "en de es fr pl pt_BR ja ko zh_CN zh_TW".split()
for folder in ("lang", "problems-lang"):
    english = {}
    for lang in langs:
        text = (recipe / folder / lang).read_text(encoding="utf-8")
        found = dict(re.findall(r'^(LOCAL11[123])="([^"]*)"$', text, re.M))
        ok = set(found) == {"LOCAL111", "LOCAL112", "LOCAL113"} and [found[k].count("%s") for k in sorted(found)] == [2, 4, 1]
        if lang == "en":
            english = found
        else:
            ok = ok and all(found[k] != english[k] for k in found)
        check(f"{folder}/{lang}: LOCAL111 to LOCAL113, placeholders 2, 4 and 1" + ("" if lang == "en" else ", translated"), ok, found)

print(f"broadcom-wl-settings: {fails} failing")
sys.exit(1 if fails else 0)
