#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check both consent summaries against the BleachBit presets we package."""

import argparse
import configparser
import json
from pathlib import Path
import re
import sys
from xml.etree import ElementTree


LANGUAGES = "en pt_BR es fr de pl ja ko zh_CN zh_TW".split()
MARKER = 'objectName: "defaultCleanupSummary"'
PO_PAIR = re.compile(
    r'^msgid ("[^\n]*"(?:\n"[^\n]*")*)\nmsgstr ("[^\n]*"(?:\n"[^\n]*")*)$',
    re.MULTILINE,
)


def checked_options(path):
    preset = configparser.ConfigParser(interpolation=None)
    with path.open(encoding="utf-8") as stream:
        preset.read_file(stream)
    tree = preset["tree"]
    # The keys with no dot control the group, not an individual cleaner option.
    return {option for option in tree if "." in option and tree.getboolean(option)}


def qml_messages(path, function):
    source = path.read_text(encoding="utf-8")
    if source.count(MARKER) != 1:
        raise ValueError(f"{path} must contain one default cleanup summary")
    block = source.split(MARKER, 1)[1].split("}", 1)[0]
    return [json.loads(message) for message in re.findall(
        rf'{function}\(("(?:[^"\\]|\\.)*")\)', block)]


def qt_messages(path):
    return {
        message.findtext("source"): message.findtext("translation")
        for context in ElementTree.parse(path).findall("context")
        if context.findtext("name") == "StorageCleanup"
        for message in context.findall("message")
        if message.find("translation") is not None
        and "type" not in message.find("translation").attrib
    }


def kde_messages(path):
    def unquote(entry):
        return "".join(json.loads(line) for line in entry.splitlines())

    results = {}
    for entry in path.read_text(encoding="utf-8").split("\n\n"):
        if any(line.startswith("#,") and "fuzzy" in line for line in entry.splitlines()):
            continue
        for source, translation in PO_PAIR.findall(entry):
            results[unquote(source)] = unquote(translation)
    return results


def check(packages, presets):
    kcm = packages / "sparky-stereo-storage-kcm"
    branding = packages / "sparky-stereo-calamares-branding"
    rows = json.loads((kcm / "tests/default-cleanup-summary.json").read_text(encoding="utf-8"))
    expected = [row["source"] for row in rows]
    described = [option for row in rows for option in row["options"]]
    selected = set.union(*(checked_options(presets / f"bleachbit-{scope}.ini")
                           for scope in ("user", "root")))
    if len(set(described)) != len(described):
        raise ValueError("The default summary describes an option more than once")
    if selected != set(described):
        missing = ", ".join(sorted(selected - set(described))) or "none"
        extra = ", ".join(sorted(set(described) - selected)) or "none"
        raise ValueError(f"Preset and summary disagree. Missing from summary: {missing}. "
                         f"Listed without a preset tick: {extra}.")
    installer_qml = branding / "usr/share/calamares/branding/sparky-stereo/StorageCleanup.qml"
    for path, function in ((installer_qml, "qsTr"), (kcm / "ui/main.qml", "i18n")):
        if qml_messages(path, function) != expected:
            raise ValueError(f"{path} does not display the reviewed default cleanup summary")

    for language in LANGUAGES:
        qt = qt_messages(branding / f"translations/calamares-sparky_{language}.ts")
        kde = kde_messages(kcm / f"po/{language}/kcm_sparkystereo_storage_cleanup.po")
        for source in expected:
            if not qt.get(source, "").strip() or qt[source] != kde.get(source):
                raise ValueError(f"{language}: missing or different consent translation: {source}")
        print(f"{language}\t{len(expected)}\tPASS")
    print(f"{len(selected)} distinct selected cleaner options\tPASS")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("packages", type=Path)
    parser.add_argument("--presets", type=Path)
    args = parser.parse_args()
    try:
        check(args.packages, args.presets or args.packages / "sparky-stereo-housekeeping/share")
    except (OSError, KeyError, ValueError, configparser.Error, ElementTree.ParseError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
