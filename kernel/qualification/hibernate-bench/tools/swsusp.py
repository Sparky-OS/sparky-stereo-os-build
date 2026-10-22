#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""swsusp.py: look into a Linux hibernation image on a raw swap disk (struct swsusp_header, kernel/power/swap.c).

  swsusp.py info  IMG                  signature, image start page, flags, crc32, number of map entries
  swsusp.py flip  IMG [--entry N]      flip one bit in the data page referenced by map entry N (default: middle of the first map page)
  swsusp.py scan  IMG PATTERN...       count occurrences of byte patterns (hex string 'hex:ab12..' or text 'txt:abc') in the whole file

Exit status: info 0 if a hibernation image is present, 1 if not; flip 0 on success; scan 0 if any pattern was found.
"""
import mmap, struct, sys

PAGE = 4096
SIG = b"S1SUSPEND"

def header(m):
    h = m[0:PAGE]
    sig = h[PAGE - 10:PAGE]
    orig = h[PAGE - 20:PAGE - 10]
    flags = struct.unpack_from("<I", h, PAGE - 24)[0]
    image = struct.unpack_from("<Q", h, PAGE - 32)[0]
    crc32 = struct.unpack_from("<I", h, PAGE - 36)[0]
    hw = struct.unpack_from("<I", h, PAGE - 40)[0]
    return sig, orig, flags, image, crc32, hw

def entries(m, image):
    off = image * PAGE
    page = m[off:off + PAGE]
    n = PAGE // 8 - 1
    vals = struct.unpack_from("<%dQ" % n, page, 0)
    nxt = struct.unpack_from("<Q", page, n * 8)[0]
    return vals, nxt

def main():
    if len(sys.argv) < 3:
        print(__doc__); return 2
    cmd, path = sys.argv[1], sys.argv[2]
    with open(path, "r+b") as f:
        size = f.seek(0, 2); f.seek(0)
        m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_WRITE if cmd == "flip" else mmap.ACCESS_READ)
        if cmd == "scan":
            found = 0
            for p in sys.argv[3:]:
                pat = bytes.fromhex(p[4:]) if p.startswith("hex:") else p[4:].encode()
                cnt = 0; pos = 0
                while True:
                    pos = m.find(pat, pos)
                    if pos < 0: break
                    cnt += 1; pos += 1
                print("%s count=%d" % (p[:24] + ("..." if len(p) > 24 else ""), cnt))
                found += cnt
            return 0 if found else 1
        sig, orig, flags, image, crc32, hw = header(m)
        present = sig.startswith(SIG)
        if cmd == "info":
            vals, nxt = entries(m, image) if present and image * PAGE < size else ((), 0)
            used = [v for v in vals if v]
            print("present=%s sig=%r orig_sig=%r flags=0x%x (platform=%d nocompress=%d crc32mode=%d) image_page=%d crc32=0x%08x entries_in_first_map=%d next=%d size=%d" %
                  (present, sig, orig, flags, flags & 1, (flags >> 1) & 1, (flags >> 2) & 1, image, crc32, len(used), nxt, size))
            return 0 if present else 1
        if cmd == "flip":
            if not present:
                print("no hibernation image"); return 1
            n = None
            for i, a in enumerate(sys.argv):
                if a == "--entry": n = int(sys.argv[i + 1])
            vals, nxt = entries(m, image)
            used = [v for v in vals if v]
            if n is None: n = len(used) // 2
            if n >= len(used):
                print("entry out of range (%d entries)" % len(used)); return 1
            pageoff = used[n] * PAGE
            pos = pageoff + 1234
            old = m[pos]
            m[pos] = old ^ 0x01
            m.flush()
            print("flipped bit 0 of byte at file offset %d (map entry %d -> page %d): 0x%02x -> 0x%02x" % (pos, n, used[n], old, old ^ 1))
            return 0
    print(__doc__); return 2

sys.exit(main())
