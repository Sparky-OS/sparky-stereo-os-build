# Held kernel patches: voice on the CSR clone dongle (ORDER 133)

**For** whoever picks up ORDER 133: two candidate patches that no kernel build applies.

They are not in `kernel/series/series.txt`, so `apply-series.sh` never sees them.
They were written on the build 16 tree for the CSR clone 0a12:0001 (bcdDevice 0x8891, LMP subversion 0x2312).
They stay held until audio through a real SCO link is proven on the dongle (CVSD and mSBC).
When that is proven they enter the series as a group with the next free number, each rebased on the kernel of that day.

The notes written with them, as they stood in the series file of their branch:

```
# ==== 45-csr-clone-sco: voice on the CSR clone 0a12:0001 bcdDevice 0x8891, LMP subversion 0x2312 (ORDER 133)
#      status: candidate, held until audio through a real SCO link is proven on the dongle in the VM (CVSD and mSBC); drop the group if voice does not work. Ours (nothing upstream, torvalds/linux
#      master d48723711bae of 2026-11-06 has the same code: btusb_main.c sets HCI_QUIRK_BROKEN_READ_VOICE_SETTING on fakes, hci_event.c zeroes sco_pkts after the fixup, force_scofix is the only way to the fixup).
#      0001 net/bluetooth/hci_event.c: hci_cc_read_buffer_size() zeroed sco_pkts after HCI_QUIRK_FIXUP_BUFFER_SIZE whenever read_voice_setting_capable() was false, so force_scofix did nothing on a fake CSR clone;
#      the zeroing stays the default (Pedro Nishiyama's 14d17c78a4b1, 2025-03-01: "A SCO connection without the proper voice_setting can cause the controller to lock up", Signed-off-by Luiz Augusto von Dentz)
#      and an explicit fixup now keeps its buffers. 0002 drivers/bluetooth/btusb.c btusb_setup_csr(): the fixup for this clone only, unless disable_scofix. Applies strictly (git apply) on the build 16 trees; the common series.txt gives all three flavours the group.
```
