#!/usr/bin/env python3
"""Check the shared QML and command-line message catalogue."""

from collections import Counter
import gettext
import io
import os
from pathlib import Path
import re
import subprocess


DOMAIN = "kcm_sparkystereo_partners"
PO_DIR = Path(__file__).resolve().parents[1] / "po"
PLURAL_COUNT = {"de": 2, "es": 2, "fr": 2, "ja": 1, "ko": 1,
                "pl": 3, "pt_BR": 2, "zh_CN": 1, "zh_TW": 1}
# Sentences added after the translations lane's last run (ORDER 70 piece 3 and later): one "CONTEXT|TEXT" per line. They may
# be untranslated in the eight languages that lane writes, and are named in the output; any other gap fails. The lane empties
# the file when it delivers them.
PENDING = Path(__file__).resolve().parents[1] / "po" / "pending-translation.txt"
PLACEHOLDERS = re.compile(r"%L?(?:[1-9][0-9]*|n)")
ACCELERATORS = re.compile(r"&&|&(?!\s)")


def format_tokens(text):
    return (frozenset(Counter(PLACEHOLDERS.findall(text)).items()),
            frozenset(Counter(ACCELERATORS.findall(text)).items()))


def pending():
    if not PENDING.exists():
        return set()
    keys = set()
    for line in PENDING.read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.startswith("#"):
            context, _, text = line.partition("|")
            text = text.replace("\\n", "\n")
            keys.add(context + "\x04" + text if context else text)
    return keys


def untranslated(path):
    """The keys msgfmt leaves out of PATH: its untranslated messages, as CONTEXT\x04TEXT."""
    out = subprocess.run(["msgattrib", "--untranslated", "--no-obsolete", "--no-wrap", "-o", "-", str(path)], check=True, capture_output=True)
    if b"msgid" not in out.stdout:
        return set()
    compiled = subprocess.run(["msgfmt", "-o", "-", "-"], input=subprocess.run(["msgen", "-"], input=out.stdout, check=True,
                              capture_output=True).stdout, check=True, capture_output=True).stdout
    return {key for key in gettext.GNUTranslations(io.BytesIO(compiled))._catalog if key}


def read_catalogue(path, template=None):
    command = ["msgfmt", "-o", "-", str(path)]
    if template is not None:
        command = ["msgfmt", "--check", "--statistics", "-o", "-", str(path)]
        subprocess.run(["msgcmp", "--no-fuzzy-matching", "--use-untranslated", str(path), str(template)], check=True)
    result = subprocess.run(command, check=True, capture_output=True,
                            env=os.environ | {"LC_ALL": "C"})
    if template is not None:
        stats = result.stderr.decode("utf-8").splitlines()
        print(f"{path.parent.name}: {stats[-1]}")
        missing = untranslated(path)
        if "fuzzy" in stats[-1] or (missing - pending()) or ("untranslated" in stats[-1] and not missing):
            raise ValueError(f"{path}: fuzzy or untranslated messages")
        if missing:
            print(f"{path.parent.name}: {len(missing)} waiting for the translations lane (po/pending-translation.txt)")
    return gettext.GNUTranslations(io.BytesIO(result.stdout))


def plural_rule(language, n):
    if PLURAL_COUNT[language] == 1:
        return 0
    if language in {"fr", "pt_BR"}:
        return int(n > 1)
    if language == "pl":
        if n == 1:
            return 0
        return 1 if 2 <= n % 10 <= 4 and not 12 <= n % 100 <= 14 else 2
    return int(n != 1)


def check_catalogue(locale, english, translation):
    expected = {}
    for key, value in english.items():
        if isinstance(key, tuple):
            message, _ = key
            for slot in range(PLURAL_COUNT[locale]):
                expected.setdefault((message, slot), set()).add(format_tokens(value))
        elif key:
            expected[key] = {format_tokens(value)}
    actual = translation._catalog
    waiting = {key for key in pending() if key not in actual}
    expected = {key: value for key, value in expected.items() if key not in waiting}
    if set(expected) != actual.keys() - {""}:
        raise ValueError(f"{locale}: compiled message keys differ from the template")
    for key, alternatives in expected.items():
        value = actual[key]
        if not value.strip() or format_tokens(value) not in alternatives:
            raise ValueError(f"{locale}: empty value or format tokens differ for {key!r}")
    plural_header = translation.info().get("plural-forms", "")
    if not re.match(rf"nplurals\s*=\s*{PLURAL_COUNT[locale]}\s*;", plural_header):
        raise ValueError(f"{locale}: incorrect number of plural forms")
    if any(translation.plural(n) != plural_rule(locale, n) for n in range(201)):
        raise ValueError(f"{locale}: incorrect plural rule")
    return len(actual) - 1


def main():
    template = PO_DIR / (DOMAIN + ".pot")
    paths = {path.parent.name: path for path in PO_DIR.glob(f"*/{DOMAIN}.po")}
    if paths.keys() != PLURAL_COUNT.keys():
        raise ValueError(f"Expected translated catalogues for {', '.join(PLURAL_COUNT)}")
    source = subprocess.check_output(["msgen", str(template)])
    compiled = subprocess.check_output(["msgfmt", "-o", "-", "-"], input=source)
    english = gettext.GNUTranslations(io.BytesIO(compiled))._catalog
    total = 0
    for language, path in sorted(paths.items()):
        total += check_catalogue(language, english, read_catalogue(path, template))
    print(f"Partners catalogues: {len(paths)} translations and English source, {total} translated values checked")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr.decode("utf-8").rstrip())
        raise SystemExit(str(error)) from error
