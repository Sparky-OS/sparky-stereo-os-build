#!/usr/bin/env python3
"""Validate every .po.patch in a directory against the exact DSC sources."""

import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile


DSC_MAP = {
    "kalgebra-stereo3d.po.patch": "kalgebra_26.04.0-1+stereo3d2.dsc",
    "kalzium-stereo3d.po.patch": "kalzium_26.04.3-1+stereo3d4.dsc",
    "kf6-kfilemetadata-stereo3d.po.patch": "kf6-kfilemetadata_6.30.0-1+stereo3d2.dsc",
    "kinfocenter-stereo3d.po.patch": "/var/tmp/sparky-lc-migration-20261020/recovered-sources/kinfocenter/kinfocenter_6.7.4-1+stereo3d1.dsc",
    "kubrick-stereo3d.po.patch": "kubrick_26.04.0-1+stereo3d2.dsc",
    "plasma-workspace-recovery.po.patch": "plasma-workspace_6.7.4-2+stereo3d2.dsc",
}

PATCH_ROOT = pathlib.Path("/K3D/temp/sparky-os/repo/source")
PATCH_NAME = pathlib.Path("/usr/bin/patch")
MSGFMT_NAME = pathlib.Path("/usr/bin/msgfmt")


def run(command, cwd=None):
    return subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)


def extract_dsc(dsc_path, destination):
    result = run(["dpkg-source", "-x", str(dsc_path), str(destination)])
    if result.returncode:
        return "dpkg-source failed: " + result.stdout.strip()
    return None


def parse_targets(patch_text):
    targets = {}
    for match in re.finditer(r"^\+\+\+\s+(?:b/)?(po/([^/\s]+)/([^/\s]+))$", patch_text, re.MULTILINE):
        targets[match.group(1)] = "po"
    return targets


def validate_patch_structure(patch_text):
    errors = []
    previous = ""
    diff_paths = set()
    target_paths = set()
    for line in patch_text.splitlines():
        stripped = line.strip()
        if line.startswith("diff --git "):
            match = re.search(r"\sa/(\S+)\s+b/(\S+)$", line)
            if match:
                diff_paths.update(match.groups())
                if match.group(1) != match.group(2):
                    errors.append("diff path mismatch: " + line[11:])
        elif stripped.startswith("---"):
            if stripped.startswith("--- a/"):
                if not previous.startswith("diff --git "):
                    errors.append("file section lacks diff --git: " + previous)
                diff_paths.add(stripped[6:])
        elif stripped.startswith("+++"):
            if stripped.startswith("+++ b/"):
                if not previous.startswith("--- "):
                    errors.append("+++ marker has no preceding ---: " + stripped[6:])
            else:
                errors.append("malformed +++ marker: " + line)
        elif stripped == "Only garbage was found":
            errors.append("GNU patch found no applicable content")
        previous = line

    for match in re.finditer(r"(?m)^\+\+\+\s+(?:b/)?(po/\S+)$", patch_text):
        target_paths.add(match.group(1))
    missing = sorted(diff_paths.difference(target_paths))
    for target in missing:
        errors.append("diff --git names " + target
                      + " but the patch adds nothing there")
    return errors


def parse_added_messages(patch_text, path):
    lines = patch_text.splitlines()
    target_lines = []
    current = None
    for line in lines:
        if line.startswith("diff --git "):
            current = None
        elif line.startswith("--- a/") and line[6:] in (path, "a/" + path):
            current = path
        elif line.startswith("--- a/") and line[6:]:
            current = None
        if current is not None and len(line) > 1 and line.startswith("+") and not line.startswith("+++ "):
            target_lines.append(line[1:])
    messages = []
    for index, line in enumerate(target_lines):
        if re.match(r"^\s*msgid\s", line):
            msgstr = next((target_lines[j] for j in range(index + 1, len(target_lines))
                           if re.match(r"^\s*msgstr\s", target_lines[j])), "")
            messages.append((line.strip(), msgstr.strip()))
    return messages


def unquote(value):
    value = re.sub(r"^\s*msg(?:id|str)\s*", "", value)
    value = value.strip()
    if value.startswith('"'):
        value = value[1:]
    if value.endswith('"'):
        value = value[:-1]
    return value


def po_has_messages(file_path, added_messages):
    try:
        text = file_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        return ["cannot read " + str(file_path) + ": " + str(error)]

    entries = []
    msg_context = None
    msgid_parts = None
    msgstr_parts = None
    mode = None

    def flush():
        if msgid_parts is not None and msgstr_parts is not None:
            entries.append((unquote(msg_context) if msg_context is not None else "",
                            unquote("".join(msgid_parts)),
                            unquote("".join(msgstr_parts))))

    for raw_line in text.splitlines() + [""]:
        line = raw_line.strip()
        if line.startswith("#~") and ("msgid " in line or "msgstr " in line):
            continue
        if line.startswith("msgctxt "):
            flush()
            msg_context = line[len("msgctxt "):].strip()
            msgid_parts = None
            msgstr_parts = None
            mode = None
        elif line.startswith("msgid "):
            flush()
            msgid_parts = [line[len("msgid "):].strip()]
            msgstr_parts = None
            mode = "msgid"
        elif line.startswith("msgstr "):
            if msgid_parts is not None:
                msgstr_parts = [line[len("msgstr "):].strip()]
                mode = "msgstr"
            else:
                msgstr_parts = None
                mode = None
        elif line.startswith('"') and line.endswith('"'):
            if mode == "msgid" and msgid_parts is not None:
                msgid_parts.append(line)
            elif mode == "msgstr" and msgstr_parts is not None:
                msgstr_parts.append(line)
    flush()

    errors = []
    for added_msgid, added_msgstr in added_messages:
        wanted_id = unquote(added_msgid)
        wanted_str = unquote(added_msgstr)
        if not wanted_str:
            errors.append("patch translation is empty: " + wanted_id)
            continue
        if not any(actual_id == wanted_id and actual_str == wanted_str
                   for _, actual_id, actual_str in entries):
            errors.append("added msgid not found with the exact non-empty msgstr: " + wanted_id)
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-root", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--translations-root", type=pathlib.Path,
                        help="read patches from this directory instead of build/sparky-os/translations")
    parser.add_argument("--only", default=None, help="comma-separated patch file names")
    parser.add_argument("--tsv", type=pathlib.Path, help="append TSV result to this file")
    args = parser.parse_args()

    if not PATCH_NAME.exists() or not MSGFMT_NAME.exists():
        print("patch and msgfmt are required", file=sys.stderr)
        return 2

    translation_root = args.translations_root
    if translation_root is None:
        translation_root = args.build_root / "sparky-os" / "translations"
    patch_names = sorted(translation_root.glob("*.po.patch"))
    if args.only:
        wanted = set(filter(None, args.only.split(",")))
        patch_names = [path for path in patch_names if path.name in wanted]

    failures = False
    for patch_path in patch_names:
        patch_text = patch_path.read_text(encoding="utf-8")
        structure_errors = validate_patch_structure(patch_text)
        garbage_patterns = (
            r"(?m)^\+diff --git ",
            r"(?m)^\+--- a/",
            r"(?m)^\+\+\+\+\s",
            r"Only garbage was found",
            r"(?m)^patch: Failed$",
        )
        if structure_errors or any(re.search(pattern, patch_text) for pattern in garbage_patterns):
            results = [("structure", "FAIL", " ; ".join(structure_errors)),
                       ("garbage", "FAIL", "malformed section marker or GNU patch garbage"),
                       ("dsc", "SKIP", ""), ("dry_run", "SKIP", ""), ("apply", "SKIP", ""),
                       ("po_check", "SKIP", "")]
        else:
            results = [("garbage", "PASS", "")]
            dsc_name = DSC_MAP.get(patch_path.name)
            if dsc_name is None:
                results.append(("dsc", "FAIL", "no DSC mapping for " + patch_path.name))
                results.extend([("dry_run", "SKIP", ""), ("apply", "SKIP", ""), ("po_check", "SKIP", "")])
                results.append(("row", "FAIL", ""))
                row = "%s\t%s\t%s\n" % (patch_path.name, "FAIL", " | ".join("%s:%s:%s" % item for item in results))
                print(row, end="")
                if args.tsv:
                    with args.tsv.open("a", encoding="utf-8") as stream:
                        stream.write(row)
                failures = True
                continue
            dsc_path = pathlib.Path(dsc_name)
            if not dsc_path.is_absolute():
                dsc_path = PATCH_ROOT / dsc_name
            with tempfile.TemporaryDirectory(prefix="validate-po-") as temporary:
                temporary_path = pathlib.Path(temporary)
                source_path = temporary_path / "source"
                extract_error = extract_dsc(dsc_path, source_path)
                if extract_error:
                    results.extend([("dsc", "FAIL", extract_error), ("dry_run", "SKIP", ""),
                                    ("apply", "SKIP", ""), ("po_check", "SKIP", "")])
                else:
                    patch_copy = source_path / patch_path.name
                    shutil.copyfile(patch_path, patch_copy)
                    dry_run = run([str(PATCH_NAME), "-p1", "--dry-run", "-i", patch_copy.name],
                                  cwd=source_path)
                    results.append(("dry_run", "PASS" if not dry_run.returncode else "FAIL",
                                    dry_run.stdout.strip().replace("\n", " | ")))
                    if not dry_run.returncode:
                        applied = run([str(PATCH_NAME), "-p1", "-i", patch_copy.name], cwd=source_path)
                        results.append(("apply", "PASS" if not applied.returncode else "FAIL",
                                        applied.stdout.strip().replace("\n", " | ")))
                        po_results = []
                        if not applied.returncode:
                            targets = parse_targets(patch_text)
                            for path in sorted(targets):
                                file_path = source_path / path
                                if not file_path.is_file():
                                    po_results.append((path, "FAIL", "target missing"))
                                    continue
                                message_errors = po_has_messages(
                                    file_path, parse_added_messages(patch_text, path))
                                checked = run([str(MSGFMT_NAME), "--check", "--statistics", path],
                                              cwd=source_path)
                                statistics = " ".join(checked.stdout.strip().split())
                                if message_errors:
                                    po_results.append((path, "FAIL", "; ".join(message_errors)))
                                elif checked.returncode:
                                    po_results.append((path, "FAIL",
                                                       checked.stdout.strip().replace("\n", " | ")))
                                elif not statistics:
                                    po_results.append((path, "FAIL", "msgfmt reported no statistics"))
                                else:
                                    po_results.append((path, "PASS", statistics))
                        results.append(("po_check", "FAIL" if any(a[1] != "PASS" for a in po_results) else "PASS",
                                        " ; ".join("%s %s %s" % item for item in po_results)))

        row_status = "FAIL" if any(state == "FAIL" for _, state, _ in results) else "PASS"
        row = "%s\t%s\t%s\n" % (patch_path.name, row_status,
                                " | ".join("%s:%s:%s" % item for item in results))
        print(row, end="")
        if args.tsv:
            with args.tsv.open("a", encoding="utf-8") as stream:
                stream.write(row)
        if row_status == "FAIL":
            failures = True
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
