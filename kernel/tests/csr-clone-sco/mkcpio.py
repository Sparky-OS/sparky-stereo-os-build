"""Write a gzip newc initramfs from a folder, adding /dev/console (char 5:1) without root.

usage: python3 -I mkcpio.py FOLDER OUT.cpio.gz
"""
import gzip
import os
import stat
import sys


def entry(out, ino, name, mode, data=b"", rdev=(0, 0), nlink=1):
    name_b = name.encode() + b"\0"
    head = "070701" + "".join("%08x" % v for v in (
        ino, mode, 0, 0, nlink, 0, len(data), 0, 0, rdev[0], rdev[1], len(name_b), 0))
    out.write(head.encode() + name_b)
    out.write(b"\0" * ((4 - (110 + len(name_b)) % 4) % 4))
    out.write(data)
    out.write(b"\0" * ((4 - len(data) % 4) % 4))


def main():
    root, dest = sys.argv[1], sys.argv[2]
    ino = 1
    with gzip.open(dest, "wb", compresslevel=6) as out:
        entry(out, ino, "dev", stat.S_IFDIR | 0o755, nlink=2)
        ino += 1
        entry(out, ino, "dev/console", stat.S_IFCHR | 0o600, rdev=(5, 1))
        for base, dirs, files in os.walk(root):
            dirs.sort()
            rel = os.path.relpath(base, root)
            if rel != ".":
                ino += 1
                entry(out, ino, rel, stat.S_IFDIR | 0o755, nlink=2)
            for f in sorted(files):
                path = os.path.join(base, f)
                ino += 1
                mode = 0o755 if os.access(path, os.X_OK) else 0o644
                with open(path, "rb") as fh:
                    entry(out, ino, os.path.normpath(os.path.join(rel, f)), stat.S_IFREG | mode, fh.read())
        entry(out, 0, "TRAILER!!!", 0)


if __name__ == "__main__":
    main()
