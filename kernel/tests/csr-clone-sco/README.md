# SCO on the CSR clone without the clone (series group 48, row 129)

Two proofs that need no Bluetooth hardware, each red on the series without group 48 and green with it.
Run both in a throwaway container: no network, no device, `--ulimit core=1`, at most four processors.

## 1. KUnit: what `hci_cc_read_buffer_size()` keeps

`bt-hci-event.kunitconfig` builds the suite `bt-hci-event-sco` (48/0003, ten cases) under QEMU x86_64.
UML does not build the edition's tree (BORE's options live in an x86-only Kconfig file).

```
python3 tools/testing/kunit/kunit.py run --arch=x86_64 --build_dir=BUILD \
  --kunitconfig=RECIPE/kernel/tests/csr-clone-sco/bt-hci-event.kunitconfig \
  --jobs=4 --timeout=600 --qemu_args='-accel tcg -smp 2' 'bt-hci-event-sco'
```

Judge the run by the parsed line `Testing complete. Ran 10 tests: passed: N, failed: M`, never by the exit status alone, and never with `--raw_output` (it counts unparsed output as one pass).
Do not start kunit.py with `python3 -I`: it imports from its own folder.

- **Green:** v7.3.4 with the whole series (`kernel/series/apply-series.sh`): 10 passed, kunit.py exit 0.
- **Red:** the series up to group 47, then only the header hunk of 48/0001 (the quirk's name, no behaviour) and 48/0003:
  `git apply --include='include/*' 48-csr-clone-sco/0001-*.patch && git apply 48-csr-clone-sco/0003-*.patch`.
  The test then compiles, and the unchanged guard fails the two cases where the driver writes the voice setting (`sco_pkts` 0 where 16 and 8 are due): 8 passed, 2 failed, kunit.py exit 1.

## 2. A virtual USB clone in a VM: what the kernel keeps

The guest boots a kernel package's own image and modules, and a USB device with the clone's ids appears on `dummy_hcd` through FunctionFS, so the real `btusb_probe()`, `btusb_setup_csr()` and the whole HCI init run.
Its HCI answers come from BlueZ's emulator: `btvirt` from Debian's bluez 5.88 source with `bluez-5.88-btdev-identity.patch`.
That patch lets `BTDEV_IDENTITY=VER:MANUFACTURER:HCI_REV:LMP_SUBVER:SCO_MTU:SCO_PKTS` (hexadecimal) make a BR/EDR server device answer Read Local Version and Read Buffer Size as that controller does, also after HCI_Reset.
A second device of the same btvirt, driven over H:4 by `headset_host.py`, is the headset side, so a SCO link can be opened from the clone.
It is not a `hci_vhci` controller on purpose: hci_vhci creates a controller by itself one second after `/dev/vhci` is opened (`vhci_open_timeout()`).
An emulated guest on a loaded machine misses that second; btvirt then prints `Failed to open Virtual HCI device` and exits, and the orphan controller times out at HCI_Reset (`Opcode 0x0c03 failed: -110`).

```
# KDIR: an unpacked linux-image package (dpkg-deb -x PKG KDIR; depmod -b KDIR RELEASE)
BTVIRT=/path/to/bluez-5.88/emulator/btvirt sh run-vm.sh KDIR RELEASE OUT \
  clone=06:000a:0810:2312:30:10 barrot1012=06:000a:0810:1012:30:10 csr8510=06:000a:22bb:22bb:30:10
```

Each case boots a fresh VM and writes `OUT/CASE/result.txt`, for example `sco=48:16 voice_setting=0x0060 connect=ok mtu=48 alt_requested=2`.
To test the series without a whole kernel build, build its Bluetooth directories against the published headers package and swap them into a copy of the package's module tree:

```
cp TREE/include/net/bluetooth/hci.h HEADERS/include/net/bluetooth/hci.h   # in an unpacked copy of linux-headers-RELEASE
make -C HEADERS M=$PWD/net-bluetooth modules
make -C HEADERS M=$PWD/drivers-bluetooth KBUILD_EXTRA_SYMBOLS=$PWD/net-bluetooth/Module.symvers modules
```

The vermagic then matches the published image; the unsigned modules taint the kernel, which the guest's log shows.

Measured on the published build 18 (7.3.4-stereo3d18), one fresh VM per case:

| Kernel | Identity | SCO MTU:packets | voice_setting | SCO connect | btusb asks for |
|---|---|---|---|---|---|
| build 18 | clone 0x2312 | 48:0 | 0x0000 | refused (ECONNREFUSED) | nothing |
| build 18 | Barrot 0x1012 | 48:0 | 0x0000 | refused | nothing |
| build 18 | genuine CSR8510 | 48:16 | 0x0000 | ok, MTU 48 | alternate setting 1 |
| build 18 + group 48's modules | clone 0x2312 | 48:16 | 0x0060 | ok, MTU 48 | alternate setting 2 |
| build 18 + group 48's modules | Barrot 0x1012 | 48:0 | 0x0000 | refused | nothing |
| build 18 + group 48's modules | genuine CSR8510 | 48:16 | 0x0000 | ok, MTU 48 | alternate setting 1 |
| build 18 + ORDER 133's held form | clone 0x2312 | 64:8 | 0x0000 | ok, MTU 64 | alternate setting 1 |

The genuine CSR8510's voice setting reads 0x0000 because btvirt's own default is 0; with it btusb asks for the 8-bit alternate setting, as it does for the held form on the clone.

Files:
- `Dockerfile`: the rig image (Debian testing, QEMU, busybox-static, BlueZ user tools, BlueZ's source and build dependencies); build it with `tools/https-only-build.sh` and a pinned `BASE`.
- `bluez-5.88-btdev-identity.patch`: the test aid for btvirt.
- `h4probe.py`: resets a btvirt server device and asks for its version and buffer sizes (checks the patch).
- `run-vm.sh`: builds a busybox initramfs with the package's 9p modules and boots one fresh VM per case (QEMU TCG, qboot, the rig container's own root read-only over 9p, results over a second 9p share).
- `guest-run.sh`: in the guest, loads the modules, starts btvirt and the headset host, makes the gadget (0a12:0001, the clone's bcdDevice), brings the clone up, records `hciconfig -a`, `voice_setting` from debugfs, a SCO connect and the kernel log.
- `ffs_clone.py`: the FunctionFS side: HCI commands from class requests on endpoint 0, events on the interrupt endpoint, ACL on the bulk endpoints; the isochronous interface has alternate setting 0 only, so the alternate setting btusb asks for shows as `set USB alt:(N) failed!` in its log.
- `headset_host.py`: the headset's host over H:4: connectable, accepts ACL and synchronous links (CVSD 0x0060), answers pairing requests without a key.
- `sco_probe.py`: a SCO socket bound to the clone connects to the headset; prints `connect=ok mtu=N` or the error.
- `userspace_sco_check.py`: checks btvirt and the headset host without a kernel (a page, then a CVSD link: `link_type=2 air_mode=2`).
- `mkcpio.py`: a newc initramfs with `/dev/console` without root.

Identities (`VER:MANUFACTURER:HCI_REV:LMP_SUBVER:SCO_MTU:SCO_PKTS`): the clone `06:000a:0810:2312:30:10`; the Barrot 8041a02 clone `06:000a:0810:1012:30:10`; a genuine CSR8510 `06:000a:22bb:22bb:30:10`.
The clone's HCI and LMP versions and manufacturer are not recorded from the device; only its bcdDevice, HCI revision, LMP subversion and SCO buffers are.
The rig cannot test the isochronous path (FunctionFS describes every endpoint descriptor as its own endpoint), so audio through the clone is proved only on real hardware.
