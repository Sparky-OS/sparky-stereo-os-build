# SPDX-License-Identifier: GPL-3.0-or-later
"""Verify selected operations using a disposable tmpfs and independent free-block accounting."""
import csv
import ctypes
import fcntl
import json
import mmap
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path("/fixture")
EVIDENCE = Path("/evidence")
ENGINE = Path(__file__).with_name("storage-cleanup.py")
MARKER = "sparky-storage-cleanup-fixture-v1"
TEMP = "tmp/sparky-preview/sparky-preview-"
THUMBS = "home/fixture/.cache/thumbnails/normal/"
ARCHIVES = "var/cache/apt/archives/"
TRASH = "home/fixture/.local/share/Trash/"
MODE = sys.argv[1]
LANGS = ("en", "pt_BR", "es", "fr", "de", "pl", "ja", "ko", "zh_CN", "zh_TW")
old = time.time() - 10 * 86400


def plant(path, n=8200, *, age=None):
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(b"F" * n)
    target.chmod(0o600)
    if age is not None:
        os.utime(target, (age, age))
    return target


def run(*args, manifest=None, lang="en"):
    return subprocess.run(
        [sys.executable, "-B", str(ENGINE), *args],
        input=manifest, text=True, capture_output=True, encoding="utf-8",
        env={**os.environ, "LC_ALL": lang, "PYTHONUTF8": "1"}, check=False,
    )


def free():
    s = os.statvfs(ROOT)
    return s.f_bfree * s.f_frsize


def reason(result):
    obj = json.loads(result.stdout)
    return obj["results"][0]["code"]


def main(table):
    if MODE == "unmarked":
        result = run("preview", "--json")
        return [verify(table, "fixture marker required", "unmarked tmpfs",
                       "exit 1 with fixture reason", (result.returncode, "fixture" in result.stderr) == (1, True))]
    (ROOT / ".fixture").write_text(MARKER)
    # Allow a child preview process to inspect this fixture-only parent's open files under Yama.
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(ctypes.c_int(0x59616D61), ctypes.c_ulong(-1), 0, 0, 0):
        raise OSError(ctypes.get_errno(), "fixture process cannot enable its own proc visibility")

    if MODE == "foreign":
        foreign = plant(TEMP + "2" * 16 + ".tmp/control", age=old)
        result = run("preview", "--json")
        (EVIDENCE / "foreign-preview.json").write_text(result.stdout)
        obj = json.loads(result.stdout)
        expected = result.returncode == 1 and obj["items"] == [] and any(
            warning["code"] == "mount" and warning["kind"] == "temporary" for warning in obj["warnings"]
        )
        return [verify(table, "child mount refused", "eligible name is a second tmpfs",
                       "explicit mount warning and sentinel retained", expected and foreign.exists())]

    apt = plant(ARCHIVES + "example_1.0_amd64.deb", 12500)
    lock = plant(ARCHIVES + "lock", 0)
    thumb = plant(THUMBS + "a" * 32 + ".png", 7300)
    browser = plant("home/fixture/.cache/mozilla/firefox/fixture.default/cache2/entries/" + "A" * 40, 16400)
    program = plant("home/fixture/.cache/mesa_shader_cache/ab/" + "d" * 38, 4077)
    temporary = plant(TEMP + "a" * 16 + ".tmp", 12002, age=old)
    trashed = plant(TRASH + "files/selected.txt", 7000)
    info = plant(TRASH + "info/selected.txt.trashinfo", 0)
    info.write_text("[Trash Info]\nPath=/home/fixture/Documents/selected.txt\nDeletionDate=2026-10-15T09:30:00\n")

    held = plant(TEMP + "b" * 16 + ".tmp", age=old)
    mapped = plant(TEMP + "c" * 16 + ".tmp", age=old)
    recent = plant(TEMP + "d" * 16 + ".tmp")
    late_open = plant(TEMP + "e" * 16 + ".tmp", age=old)
    unregistered = plant(TEMP + "f" * 16 + ".tmp", age=old)
    registered = {}
    for path in (temporary, held, mapped, recent, late_open):
        s = path.stat()
        registered[path.name] = (s.st_dev, s.st_ino, s.st_uid, s.st_mode, s.st_nlink, s.st_size,
                                 s.st_blocks, s.st_mtime_ns, s.st_ctime_ns)
    (ROOT / ".temporary.json").write_text(json.dumps(registered))
    replacement = plant(THUMBS + "b" * 32 + ".png")
    permission = plant(THUMBS + "c" * 32 + ".png")
    sparse = plant(THUMBS + "d" * 32 + ".png", 1)
    with sparse.open("r+b") as handle:
        handle.truncate(1024 * 1024)
    unselected = plant(THUMBS + "f" * 32 + ".png")
    batch_item = plant(THUMBS + "0" * 32 + ".png")
    personal = plant("home/fixture/Documents/personal.txt")
    control = plant("tmp/leave-this-personal.tmp", age=old)
    local_mail = plant("var/mail/fixture")
    state = plant("home/fixture/.local/state/stereo-policy/files")
    session = plant("home/fixture/.mozilla/firefox/fixture.default/sessionstore.jsonlz4")
    orphan = plant(TRASH + "files/no-metadata.txt")
    partial = plant(ARCHIVES + "partial/example_1.1_amd64.deb")
    symlink = ROOT / (THUMBS + "e" * 32 + ".png")
    symlink.symlink_to(personal)
    hardlink = ROOT / (THUMBS + "9" * 32 + ".png")
    os.link(personal, hardlink)

    protected = {
        "current journal": plant("var/log/journal/sample/system.journal", 12200),
        "archived journal": plant("var/log/journal/sample/system@older.journal", 9345, age=old),
        "rotated text log": plant("var/log/service.log.2.gz", 700, age=old),
        "crash evidence": plant("var/lib/systemd/coredump/core.keep.zst", 15400, age=old),
        "Flatpak runtime representative data": plant("var/lib/flatpak/runtime/example/files/data", 21111),
        "Debian-managed /var/tmp": plant("var/tmp/age-managed.tmp", 8193, age=old),
    }
    with (EVIDENCE / "protected-inventory.tsv").open("w") as stream:
        writer = csv.writer(stream, delimiter="\t")
        writer.writerow(("kind", "fixture_path", "allocation_bytes", "eligibility"))
        for label, target in protected.items():
            writer.writerow((label, "/" + str(target.relative_to(ROOT)), target.stat().st_blocks * 512,
                             "excluded"))

    checks = []
    with mapped.open("rb") as file:
        mapping = mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ)
    with mapping, held.open("rb"):
        result = run("preview", "--json")
        (EVIDENCE / "preview.json").write_text(result.stdout)
        assert result.returncode == 0, result.stderr + result.stdout
        manifest = result.stdout
        obj = json.loads(manifest)
        rows = {ROOT / item["path"][1:]: item for item in obj["items"]}
        text = run("preview")
        (EVIDENCE / "preview.txt").write_text(text.stdout)
        checks.append(verify(table, "text matches JSON", "different type and two output modes",
                             "every ID and loss sentence appears", text.returncode == 0 and all(
                                 item["id"] in text.stdout and item["loss"] in text.stdout for item in rows.values())))
        for path, label in {
            held:"open temporary", mapped:"mapped temporary", recent:"recent temporary",
            unregistered:"matching name without producer record",
            personal:"personal file", control:"blanket tmp control", local_mail:"system mail",
            state:"stereo state", session:"browser recovery", orphan:"orphan trash",
            partial:"partial APT download", symlink:"symbolic link", hardlink:"hard link",
            **{target:label for label,target in protected.items()},
        }.items():
            checks.append(verify(table, label, str(path.relative_to(ROOT)),
                                 "present in fixture and absent from preview", path.exists() and path not in rows))
        for lang in LANGS:
            localized = run("preview", "--json", lang=lang)
            messages = json.loads(localized.stdout)["items"]
            checks.append(verify(table, f"CLI locale {lang}", "English is the comparison",
                                 "same IDs and localized loss sentences",
                                 localized.returncode == 0 and len(messages) == len(rows) and all(
                                     local["id"] == baseline["id"]
                                     and (lang == "en" or local["loss"] != baseline["loss"])
                                     for local, baseline in zip(messages, rows.values(), strict=True))))

        def remove(path):
            return run("clean", rows[path]["id"], manifest=manifest)

        with lock.open("r+b") as handle:
            fcntl.lockf(handle, fcntl.LOCK_EX)
            fail = remove(apt)
            checks.append(verify(table, "APT lock held", "second process holds POSIX cache lock",
                                 "exit 1 with apt_busy and archive retained",
                                 fail.returncode == 1 and reason(fail) == "apt_busy" and apt.exists()))
        with late_open.open("rb"):
            os.utime(late_open, (old, old))
            fail = remove(late_open)
            checks.append(verify(table, "temporary opens after preview", "explicitly selected old file opened",
                                 "exit 1 with open reason and file retained",
                                 fail.returncode == 1 and reason(fail) == "open" and late_open.exists()))
        replacement.unlink()
        plant(str(replacement.relative_to(ROOT)), 4100)
        fail = remove(replacement)
        checks.append(verify(table, "stale preview", "previewed name now points to another file",
                             "exit 1 with changed reason and replacement retained",
                             fail.returncode == 1 and reason(fail) == "changed" and replacement.exists()))
        permission.parent.chmod(0o500)
        try:
            fail = remove(permission)
            (EVIDENCE / "failure.json").write_text(fail.stdout)
            checks.append(verify(table, "explicit permission failure", "parent is not writable",
                                 "exit 1 and permission reason", fail.returncode == 1 and
                                 reason(fail) == "permission" and permission.exists()))
        finally:
            permission.parent.chmod(0o700)
        info.parent.chmod(0o500)
        try:
            fail = remove(trashed)
            checks.append(verify(table, "Trash sidecar permission", "metadata directory is not writable",
                                 "exit 1 with permission reason and both files retained",
                                 fail.returncode == 1 and reason(fail) == "permission"
                                 and trashed.exists() and info.exists()))
        finally:
            info.parent.chmod(0o700)

        for path in (apt, thumb, browser, program, temporary, trashed, sparse):
            item = rows[path]
            before = free()
            applied = remove(path)
            after = free()
            obj = json.loads(applied.stdout)["results"][0]
            freed = after - before
            checks.append(verify(table, f'{item["kind"]}: {path.name}',
                                 f'logical={item["logical_bytes"]}, free_before={before}',
                                 f'preview={item["allocated_bytes"]}, measured={freed}, engine={obj["allocated_bytes_removed"]}',
                                 applied.returncode == 0 and not path.exists()
                                 and (path != trashed or not info.exists())
                                 and freed > 0 and freed == item["allocated_bytes"] == obj["allocated_bytes_removed"]))
        checks.append(verify(table, "sparse file control", "logical size is 1 MiB",
                             f'allocated={rows[sparse]["allocated_bytes"]}',
                             rows[sparse]["allocated_bytes"] < rows[sparse]["logical_bytes"]))
        checks.append(verify(table, "preview is not bulk consent", "unselected eligible thumbnail",
                             "unselected and protected files still exist",
                                 unselected.exists() and held.exists() and mapped.exists() and unregistered.exists() and all(
                                 path.exists() for path in protected.values())))
        bogus = "0" * 64
        refused = run("clean", bogus, manifest=manifest)
        checks.append(verify(table, "unknown selection", bogus, "exit 1 with invalid reason",
                             refused.returncode == 1 and reason(refused) == "invalid"))
        forged = json.loads(manifest)
        for item in forged["items"]:
            if item["id"] == rows[batch_item]["id"]:
                item["path"] = "/" + str(personal.relative_to(ROOT))
        refused = run("clean", rows[batch_item]["id"], manifest=json.dumps(forged))
        checks.append(verify(table, "forged personal path", "receipt points at a personal file",
                             "exit 1 and personal file retained", refused.returncode == 1
                             and reason(refused) == "invalid" and personal.exists()))
        before = free()
        batch = run("clean", bogus, rows[batch_item]["id"], manifest=manifest)
        after = free()
        results = json.loads(batch.stdout)["results"]
        (EVIDENCE / "mixed-results.json").write_text(batch.stdout)
        checks.append(verify(table, "mixed selection", "unknown ID followed by a valid ID",
                             f"invalid and removed results, exit 1, measured={after - before}",
                             batch.returncode == 1 and [item["code"] for item in results] == ["invalid", "removed"]
                             and after - before == rows[batch_item]["allocated_bytes"] and not batch_item.exists()))
    return checks


def verify(writer, claim, control, observed, passed):
    writer.writerow((claim, control, observed, "PASS" if passed else "FAIL"))
    return passed


with (EVIDENCE / f"{MODE}.tsv").open("w", newline="") as stream:
    table = csv.writer(stream, delimiter="\t", lineterminator="\n")
    table.writerow(("claim", "control", "observed", "verdict"))
    result = main(table)
    print(f"{sum(result)}/{len(result)} checks passed")
    sys.exit(not all(result))
