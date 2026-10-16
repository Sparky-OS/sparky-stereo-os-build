#!/usr/bin/env python3
"""layout.py ISO...  : print the MBR partition entries, the GPT header and entries, and whether GPT entries overlap."""
import struct, sys, uuid

def mbr(f):
    f.seek(0); b = f.read(512)
    out = ["MBR signature %02x%02x" % (b[510], b[511])]
    for i in range(4):
        e = b[446 + 16 * i: 462 + 16 * i]
        st, typ = e[0], e[4]
        lba, n = struct.unpack("<II", e[8:16])
        if typ or n or st:
            out.append("  MBR#%d boot=0x%02x type=0x%02x start=%d sectors=%d (end=%d)" % (i + 1, st, typ, lba, n, lba + n - 1))
    return out

def gpt(f):
    f.seek(512); h = f.read(92)
    if h[:8] != b"EFI PART":
        return ["  no GPT header at LBA 1"]
    (rev, hs, crc, _r, cur, bak, first, last) = struct.unpack("<IIIIQQQQ", h[8:56])
    guid = uuid.UUID(bytes_le=h[56:72])
    (eslba, nent, esz, ecrc) = struct.unpack("<QIII", h[72:92])
    out = ["  GPT header: first usable LBA %d, last usable %d, backup header LBA %d, entries at LBA %d, %d slots x %d bytes" % (first, last, bak, eslba, nent, esz)]
    f.seek(eslba * 512); arr = f.read(nent * esz)
    ents = []
    for i in range(nent):
        e = arr[i * esz:(i + 1) * esz]
        t = uuid.UUID(bytes_le=e[:16])
        if t.int == 0:
            continue
        s, l = struct.unpack("<QQ", e[32:48])
        name = e[56:128].decode("utf-16le", "replace").rstrip("\x00")
        ents.append((i + 1, str(t), s, l, name))
        out.append("  GPT#%d type=%s start=%d end=%d name=%r" % (i + 1, t, s, l, name))
    ov = [(a[0], b[0]) for i, a in enumerate(ents) for b in ents[i + 1:] if a[2] <= b[3] and b[2] <= a[3]]
    out.append("  overlapping GPT entry pairs: %s" % (ov or "none"))
    return out

for p in sys.argv[1:]:
    with open(p, "rb") as f:
        f.seek(0, 2); size = f.tell()
        print("== %s (%d bytes = %d sectors)" % (p, size, size // 512))
        for l in mbr(f) + gpt(f):
            print(l)
