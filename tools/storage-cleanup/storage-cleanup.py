#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Storage cleanup preview and selected removal, for the isolated milestone fixture."""
from contextlib import ExitStack, contextmanager
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import time

ROOT = Path("/fixture")
MARKER = "sparky-storage-cleanup-fixture-v1"
LANGUAGES = json.loads(Path(__file__).with_name("messages.json").read_text(encoding="utf-8"))
MIN_AGE = 7 * 86400
DIRECTORY = os.O_DIRECTORY | os.O_NOFOLLOW
RULES = {
    "apt": ("var/cache/apt/archives", r"[a-z0-9][a-z0-9+.-]*_[A-Za-z0-9.+~:%-]+_[a-z0-9-]+\.deb"),
    "thumbnails": ("home/fixture/.cache/thumbnails/normal", r"[a-f0-9]{32}\.png"),
    "browser": ("home/fixture/.cache/mozilla/firefox/fixture.default/cache2/entries", r"[A-F0-9]{40}"),
    "program": ("home/fixture/.cache/mesa_shader_cache/ab", r"[a-f0-9]{38}"),
    "temporary": ("tmp/sparky-preview", r"sparky-preview-[a-f0-9]{16}\.tmp"),
    "trash": ("home/fixture/.local/share/Trash/files", r"[^/]+"),
}
TRASH_INFO = "home/fixture/.local/share/Trash/info"
APT_LOCK = "var/cache/apt/archives/lock"


class Refusal(Exception):
    """A localizable decision with a stable machine-readable code."""


def mount_id(fd):
    with open(f"/proc/self/fdinfo/{fd}", encoding="ascii") as info:
        for line in info:
            if line.startswith("mnt_id:"):
                return int(line.split()[1])
    raise Refusal("mount")


@contextmanager
def opened(path, flags, parent=None):
    fd = os.open(path, flags, dir_fd=parent)
    try:
        yield fd
    finally:
        os.close(fd)


def fingerprint(s):
    return (s.st_dev, s.st_ino, s.st_uid, s.st_mode, s.st_nlink, s.st_size,
            s.st_blocks, s.st_mtime_ns, s.st_ctime_ns)


def inode(s):
    return (s.st_dev, s.st_ino)


def open_inodes(device):
    """Use the isolated fixture PID namespace. Missing visibility fails closed."""
    seen = set()
    wanted = (os.major(device), os.minor(device))
    for proc in Path("/proc").iterdir():
        if not proc.name.isdecimal() or proc.name == str(os.getpid()):
            continue
        try:
            for link in (proc / "fd").iterdir():
                try:
                    s = link.stat()
                except FileNotFoundError:
                    continue
                if s.st_dev == device:
                    seen.add(inode(s))
            # A mapping can keep the storage allocated after the descriptor closes.
            for line in (proc / "maps").read_text(errors="replace").splitlines():
                fields = line.split(maxsplit=5)
                if fields[4] != "0":
                    major_minor = tuple(int(x, 16) for x in fields[3].split(":"))
                    if major_minor == wanted:
                        seen.add((device, int(fields[4])))
        except (FileNotFoundError, ProcessLookupError):
            continue
        except PermissionError as exc:
            raise Refusal("visibility") from exc
    return seen


class Fixture:
    def __init__(self, fd):
        self.root = fd
        self.device = os.fstat(fd).st_dev
        self.mount = mount_id(fd)
        mounts = Path("/proc/self/mountinfo").read_text().splitlines()
        if not any(line.split()[0] == str(self.mount) and line.split()[4] == str(ROOT)
                   and line.split(" - ", 1)[1].split()[0] == "tmpfs" for line in mounts):
            raise Refusal("fixture")
        with opened(".fixture", os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, fd) as marker:
            if not stat.S_ISREG(os.fstat(marker).st_mode) or os.read(marker, 128) != MARKER.encode():
                raise Refusal("fixture")
        self.temporary_files = self.register_view()

    def same_mount(self, fd):
        if os.fstat(fd).st_dev != self.device or mount_id(fd) != self.mount:
            raise Refusal("mount")

    @contextmanager
    def directory(self, path):
        with ExitStack() as stack:
            parent = self.root
            for part in path.split("/"):
                parent = stack.enter_context(opened(part, os.O_RDONLY | DIRECTORY, parent))
                self.same_mount(parent)
            yield parent

    @contextmanager
    def file(self, path, flags=os.O_PATH):
        directory, name = path.rsplit("/", 1)
        with self.directory(directory) as parent:
            with opened(name, flags | os.O_NOFOLLOW, parent) as fd:
                self.same_mount(fd)
                s = os.fstat(fd)
                if not stat.S_ISREG(s.st_mode) or s.st_nlink != 1 or s.st_uid != os.geteuid():
                    raise Refusal("protected")
                yield parent, name, s, fd

    @contextmanager
    def apt_lock(self, kind):
        if kind != "apt":
            yield
            return
        with self.file(APT_LOCK, os.O_RDWR | os.O_NONBLOCK) as (_, _, _, fd):
            try:
                fcntl.lockf(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as exc:
                raise Refusal("apt_busy") from exc
            yield

    def item_paths(self, kind, path):
        if kind == "trash":
            return [path, f"{TRASH_INFO}/{path.rsplit('/', 1)[1]}.trashinfo"]
        return [path]

    def check(self, kind, files, in_use):
        for _, _, s, _ in files:
            if inode(s) in in_use:
                raise Refusal("open")
        if kind == "temporary":
            s = files[0][2]
            if time.time() - max(s.st_mtime, s.st_atime) < MIN_AGE:
                raise Refusal("recent")
            if self.temporary_files.get(files[0][1]) != list(fingerprint(s)):
                raise Refusal("protected")

    def register_view(self):
        # Entries come from the fixture's producer. A name alone is no proof of origin.
        try:
            with opened(".temporary.json", os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, self.root) as fd:
                metadata = os.fstat(fd)
                if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.geteuid() or metadata.st_nlink != 1:
                    raise Refusal("protected")
                self.same_mount(fd)
                entries = json.loads(os.read(fd, 1048576))
                if not isinstance(entries, dict):
                    raise ValueError
                return entries
        except FileNotFoundError:
            return {}
        except (UnicodeError, ValueError) as exc:
            raise Refusal("invalid") from exc

    def metadata(self, kind, path, files):
        first = files[0][2]
        records = [fingerprint(s) for _, _, s, _ in files]
        key = (kind, path, self.mount, records)
        return {
            "id": hashlib.sha256(json.dumps(key).encode()).hexdigest(),
            "kind": kind,
            "path": "/" + path,
            "allocated_bytes": sum(s.st_blocks * 512 for _, _, s, _ in files),
            "logical_bytes": first.st_size,
        }

    def inspect(self, kind, path, in_use):
        with ExitStack() as stack:
            files = [stack.enter_context(self.file(name)) for name in self.item_paths(kind, path)]
            self.check(kind, files, in_use)
            if kind == "trash":
                # Read the paired metadata, without accepting paths out of this fixture.
                info = files[1]
                with opened(info[1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, info[0]) as handle:
                    if fingerprint(os.fstat(handle)) != fingerprint(info[2]):
                        raise Refusal("changed")
                    data = os.read(handle, 4096)
                if not re.fullmatch(
                    rb"\[Trash Info\]\nPath=/[^\r\n]+\nDeletionDate=\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\n",
                    data,
                ):
                    raise Refusal("protected")
            return self.metadata(kind, path, files)

    def preview(self):
        in_use = open_inodes(self.device)
        items = []
        warnings = []
        for kind, (directory, pattern) in RULES.items():
            try:
                with self.directory(directory) as fd:
                    names = sorted(os.listdir(fd))
            except FileNotFoundError:
                continue
            except (Refusal, OSError) as exc:
                warnings.append((kind, error_code(exc)))
                continue
            for name in names:
                if not re.fullmatch(pattern, name):
                    continue
                try:
                    items.append(self.inspect(kind, f"{directory}/{name}", in_use))
                except Refusal as exc:
                    if exc.args[0] in {"mount", "visibility", "permission"}:
                        warnings.append((kind, exc.args[0]))
                except OSError as exc:
                    code = error_code(exc)
                    if code != "changed":
                        warnings.append((kind, code))
        return items, sorted(set(warnings))

    def apply(self, item):
        kind = item["kind"]
        directory, pattern = RULES[kind]
        path = item["path"]
        if not isinstance(path, str) or not path.startswith(f"/{directory}/"):
            raise Refusal("invalid")
        name = path.removeprefix(f"/{directory}/")
        if name in {".", ".."} or not re.fullmatch(pattern, name):
            raise Refusal("invalid")
        path = path[1:]
        with self.apt_lock(kind):
            in_use = open_inodes(self.device)
            current = self.inspect(kind, path, in_use)
            if current["id"] != item["id"]:
                raise Refusal("changed")
            with ExitStack() as stack:
                files = [stack.enter_context(self.file(name)) for name in self.item_paths(kind, path)]
                self.check(kind, files, open_inodes(self.device))
                if self.metadata(kind, path, files)["id"] != item["id"]:
                    raise Refusal("changed")
                for parent, leaf, s, _ in files:
                    if fingerprint(os.stat(leaf, dir_fd=parent, follow_symlinks=False)) != fingerprint(s):
                        raise Refusal("changed")
                    if not os.access(".", os.W_OK | os.X_OK, dir_fd=parent, effective_ids=True):
                        raise Refusal("permission")
                removed = 0
                try:
                    for parent, leaf, s, _ in files:
                        os.unlink(leaf, dir_fd=parent)
                        removed += s.st_blocks * 512
                except OSError as exc:
                    return removed, error_code(exc)
        return removed, None


def error_code(exc):
    if isinstance(exc, Refusal):
        return exc.args[0]
    if isinstance(exc, PermissionError) or exc.errno == errno.EROFS:
        return "permission"
    if isinstance(exc, FileNotFoundError) or exc.errno in {errno.ENOTDIR, errno.ELOOP}:
        return "changed"
    return "io"


def catalog():
    lang = os.environ.get("LC_ALL") or os.environ.get("LC_MESSAGES") or os.environ.get("LANG") or "en"
    lang = lang.split(".")[0].replace("-", "_")
    return LANGUAGES.get(lang, LANGUAGES.get(lang.split("_")[0], LANGUAGES["en"]))


def main(argv):
    messages = catalog()
    if argv in (["--help"], ["-h"]):
        print(messages["usage"])
        return 0
    if argv not in (["preview"], ["preview", "--json"]) and not (argv[:1] == ["clean"] and len(argv) > 1):
        print(messages["usage"], file=sys.stderr)
        return 2
    try:
        with opened(ROOT, os.O_RDONLY | DIRECTORY) as fd:
            rig = Fixture(fd)
            if argv[0] == "preview":
                items, warnings = rig.preview()
                for item in items:
                    item["loss"] = messages[item["kind"]]
                if len(argv) == 2:
                    print(json.dumps({"version": 1, "items": items, "warnings": [
                        {"kind": kind, "code": code, "message": messages[code]} for kind, code in warnings
                    ]}, ensure_ascii=False))
                else:
                    print(messages["preview"])
                    for item in items:
                        print(f'{item["id"]}  {item["allocated_bytes"]} B  {json.dumps(item["path"], ensure_ascii=False)}  {item["loss"]}')
                    for kind, code in warnings:
                        print(f"{kind}: {messages[code]}", file=sys.stderr)
                return int(bool(warnings))
            try:
                manifest = json.load(sys.stdin)
                rows = manifest["items"]
                if manifest["version"] != 1 or not isinstance(rows, list):
                    raise ValueError
                by_id = {row["id"]: row for row in rows if row["kind"] in RULES}
            except (ValueError, KeyError, TypeError) as exc:
                raise Refusal("invalid") from exc
            results = []
            failed = False
            for selected in argv[1:]:
                item = by_id.get(selected)
                try:
                    if item is None:
                        raise Refusal("invalid")
                    removed, code = rig.apply(item)
                except (OSError, Refusal, KeyError) as exc:
                    removed, code = 0, error_code(exc) if not isinstance(exc, KeyError) else "invalid"
                failed |= code is not None
                results.append({"id": selected, "allocated_bytes_removed": removed,
                                "code": code or "removed", "message": messages[code or "removed"]})
            print(json.dumps({"version": 1, "results": results}, ensure_ascii=False))
            return int(failed)
    except (OSError, Refusal) as exc:
        code = "fixture" if isinstance(exc, FileNotFoundError) else error_code(exc)
        print(messages[code], file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
