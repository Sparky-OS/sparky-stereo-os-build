#!/usr/bin/env python3
"""Validate .po.patch files and their exact DSC sources."""

import argparse
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
    "kinfocenter-stereo3d.po.patch": "kinfocenter_6.7.4-1+stereo3d1.dsc",
    "kubrick-stereo3d.po.patch": "kubrick_26.04.0-1+stereo3d2.dsc",
    "plasma-workspace-recovery.po.patch": "plasma-workspace_6.7.4-2+stereo3d2.dsc",
}
PATCH_ROOT = pathlib.Path("/K3D/temp/sparky-os/repo/source")
PATCH_NAME = pathlib.Path("/usr/bin/patch")
MSGFMT_NAME = pathlib.Path("/usr/bin/msgfmt")
HUNK_HEADER = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def run(command, cwd=None):
    return subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT)


def extract_dsc(dsc_path, destination):
    result = run(["dpkg-source", "-x", str(dsc_path), str(destination)])
    if result.returncode:
        return "dpkg-source failed: " + result.stdout.strip()
    return None


def clean_diff_path(value, side):
    if side == "old":
        return value if value == "/dev/null" else value[2:] if value.startswith("a/") else value
    return value[2:] if value.startswith("b/") else value


def parse_patch_sections(patch_text, errors, patch_name):
    sections = []
    lines = patch_text.splitlines()
    first_diff = next((index for index, line in enumerate(lines)
                       if line.startswith("diff --git ")), None)
    if first_diff is None:
        errors.append("%s: no file section" % patch_name)
        return sections
    index = first_diff
    section = None
    hunk_open = False
    old_count = new_count = counted_old = counted_new = 0
    hunk_start_line = 0
    last_hunk_line = False

    def close_section():
        nonlocal section
        if section is not None:
            sections.append(section)
            section = None

    def close_hunk():
        nonlocal hunk_open, counted_old, counted_new, hunk_start_line, last_hunk_line
        if hunk_open and (counted_old != old_count or counted_new != new_count):
            errors.append("%s: hunk at line %d: expected %d/%d lines, got %d/%d"
                          % (patch_name, hunk_start_line, old_count, new_count,
                             counted_old, counted_new))
        hunk_open = False
        counted_old = counted_new = 0
        hunk_start_line = 0
        last_hunk_line = False

    while index < len(lines):
        number = index + 1
        line = lines[index]
        index += 1

        if line == r"\ No newline at end of file":
            if section is not None and last_hunk_line:
                continue
            errors.append("%s: line %d: misplaced no-newline marker" % (patch_name, number))
            continue

        if hunk_open and (not line or line[:1] in {"+", "-", " "}):
            first = line[:1] if line else " "
            if first == "+" or first == "-":
                section["added"].append(line[1:])
            if first != "-":
                counted_new += 1
            if first != "+":
                counted_old += 1
            if counted_old > old_count or counted_new > new_count:
                errors.append("%s: hunk at line %d: line beyond header counts"
                              % (patch_name, hunk_start_line))
            elif counted_old == old_count and counted_new == new_count:
                hunk_open = False
                last_hunk_line = True
                continue
            last_hunk_line = True
            continue

        if hunk_open:
            close_hunk()

        if line.startswith("diff --git "):
            close_hunk()
            close_section()
            match = re.match(r"^diff --git\s+a/(\S+)\s+b/(\S+)$", line)
            if not match:
                errors.append("%s: line %d: malformed diff header" % (patch_name, number))
                continue
            old_path = clean_diff_path(match.group(1), "old")
            new_path = clean_diff_path(match.group(2), "new")
            if old_path != "/dev/null" and old_path != new_path:
                errors.append("%s: line %d: diff paths differ: %s -> %s"
                              % (patch_name, number, old_path, new_path))
            section = {"old_path": old_path, "new_path": new_path, "added": []}
            continue

        if section is None:
            errors.append("%s: line %d: line outside file section: %s"
                          % (patch_name, number, line or "<blank>"))
            continue

        if line.startswith("--- "):
            close_hunk()
            section["old_path"] = clean_diff_path(line[4:].split()[0], "old")
        elif line.startswith("+++ "):
            close_hunk()
            section["new_path"] = clean_diff_path(line[4:].split()[0], "new")
        elif line.startswith("@@ "):
            close_hunk()
            match = HUNK_HEADER.match(line)
            if not match:
                errors.append("%s: line %d: malformed hunk header" % (patch_name, number))
                continue
            old_start, old_length, new_start, new_length = match.groups()
            old_count = int(old_length) if old_length is not None else 1
            new_count = int(new_length) if new_length is not None else 1
            counted_old = counted_new = 0
            hunk_start_line = number
            hunk_open = True
        elif line.startswith(("index ", "old mode ", "new mode ", "deleted file mode ",
                              "new file mode ", "similarity index ", "rename from ",
                              "rename to ")):
            pass
        else:
            errors.append("%s: line %d: line outside hunk: %s"
                          % (patch_name, number, line or "<blank>"))

    close_hunk()
    close_section()
    return sections


def validate_patch_structure(patch_text, patch_name):
    errors = []
    parse_patch_sections(patch_text, errors, patch_name)
    if re.search(r"(?m)^\+diff --git ", patch_text):
        errors.append("%s: malformed section marker" % patch_name)
    if "Only garbage was found" in patch_text:
        errors.append("%s: GNU patch found no applicable content" % patch_name)
    return errors


def parse_targets(patch_text):
    targets = set()
    for match in re.finditer(r"(?m)^\+\+\+\s+(?:b/)?(po/\S+)$", patch_text):
        targets.add(match.group(1))
    return targets


def parse_added_messages(patch_text, path):
    sections = parse_patch_sections(patch_text, [], path)
    target_lines = []
    for section in sections:
        if path in (section["old_path"], section["new_path"]):
            target_lines.extend(section["added"])
    messages = []
    index = 0
    context = None
    while index < len(target_lines):
        stripped = target_lines[index].strip()
        if stripped.startswith("msgctxt "):
            context = stripped
            index += 1
            continue
        if not stripped.startswith("msgid "):
            index += 1
            continue
        msgid_parts = [stripped]
        index += 1
        while index < len(target_lines) and not target_lines[index].startswith("msgstr "):
            msgid_parts.append(target_lines[index].strip())
            index += 1
        if index >= len(target_lines):
            break
        msgstr_parts = [target_lines[index].strip()]
        index += 1
        while index < len(target_lines) and target_lines[index].startswith('"'):
            msgstr_parts.append(target_lines[index].strip())
            index += 1
        messages.append((context, "\n".join(msgid_parts), "\n".join(msgstr_parts)))
        context = None
    return messages


def unquote(value):
    value = re.sub(r"^\s*msg(?:ctxt|id|str)\s*", "", value).strip()
    if value.startswith('"') and value.endswith('"'):
        value = value[1:-1]
    return value


def parse_po_entries(file_path):
    text = file_path.read_text(encoding="utf-8")
    entries = []
    context = None
    msgid_parts = None
    msgstr_parts = None
    mode = None

    def flush():
        if msgid_parts is not None and msgstr_parts is not None:
            entries.append((
                unquote(context) if context is not None else "",
                unquote("\n".join(msgid_parts)),
                unquote("\n".join(msgstr_parts)),
            ))

    for raw_line in text.splitlines() + [""]:
        line = raw_line.strip()
        if line.startswith("#~"):
            continue
        if line.startswith("msgctxt "):
            flush()
            context = line[len("msgctxt "):].strip()
            msgid_parts = None
            msgstr_parts = None
            mode = None
        elif line.startswith("msgid "):
            flush()
            context = context if context is not None else None
            msgid_parts = [line[len("msgid "):].strip()]
            msgstr_parts = None
            mode = "msgid"
        elif line.startswith("msgstr "):
            if msgid_parts is not None:
                msgstr_parts = [line[len("msgstr "):].strip()]
                mode = "msgstr"
            else:
                msgid_parts = None
                msgstr_parts = None
                mode = None
        elif line.startswith('"') and line.endswith('"'):
            if mode == "msgid" and msgid_parts is not None:
                msgid_parts.append(line)
            elif mode == "msgstr" and msgstr_parts is not None:
                msgstr_parts.append(line)
        elif not line:
            flush()
            context = None
            msgid_parts = None
            msgstr_parts = None
            mode = None
    # Clear the context before msgid only, not after a completed entry.
    return [(entry_context, entry_id, entry_str)
            for entry_context, entry_id, entry_str in entries]


def po_has_messages(file_path, added_messages):
    try:
        entries = parse_po_entries(file_path)
    except (OSError, UnicodeError) as error:
        return ["cannot read %s: %s" % (file_path, error)]
    errors = []
    for added_context, added_msgid, added_msgstr in added_messages:
        wanted_context = unquote(added_context) if added_context is not None else ""
        wanted_id = unquote(added_msgid)
        wanted_str = unquote(added_msgstr)
        if not wanted_str:
            errors.append("patch translation is empty: " + wanted_id)
            continue
        if not any(actual_context == wanted_context and actual_id == wanted_id
                   and actual_str == wanted_str for actual_context, actual_id, actual_str in entries):
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
        structure_errors = validate_patch_structure(patch_text, patch_path.name)
        if structure_errors:
            results = [("structure", "FAIL", " ; ".join(structure_errors)),
                       ("dsc", "SKIP", ""), ("dry_run", "SKIP", ""), ("apply", "SKIP", ""),
                       ("po_check", "SKIP", "")]
        else:
            results = [("structure", "PASS", "")]
            dsc_name = DSC_MAP.get(patch_path.name)
            if dsc_name is None:
                results.append(("dsc", "FAIL", "no DSC mapping for " + patch_path.name))
                results.extend([("dry_run", "SKIP", ""), ("apply", "SKIP", ""),
                                ("po_check", "SKIP", "")])
            else:
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
                            applied = run([str(PATCH_NAME), "-p1", "-i", patch_copy.name],
                                          cwd=source_path)
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
                            results.append(("po_check", "FAIL" if any(a[1] != "PASS" for a in po_results)
                                            else "PASS",
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
