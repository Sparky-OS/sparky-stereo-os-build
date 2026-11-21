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
PLACEHOLDERS = re.compile(r"%L?(?:[1-9][0-9]*|n)")
ACCELERATORS = re.compile(r"&&|&(?!\s)")


def format_tokens(text):
    return (frozenset(Counter(PLACEHOLDERS.findall(text)).items()),
            frozenset(Counter(ACCELERATORS.findall(text)).items()))


def read_catalogue(path, template=None):
    command = ["msgfmt", "-o", "-", str(path)]
    if template is not None:
        command = ["msgfmt", "--check", "--statistics", "-o", "-", str(path)]
        subprocess.run(["msgcmp", "--no-fuzzy-matching", str(path), str(template)], check=True)
    result = subprocess.run(command, check=True, capture_output=True,
                            env=os.environ | {"LC_ALL": "C"})
    if template is not None:
        stats = result.stderr.decode("utf-8").splitlines()
        print(f"{path.parent.name}: {stats[-1]}")
        if "fuzzy" in stats[-1] or "untranslated" in stats[-1]:
            raise ValueError(f"{path}: fuzzy or untranslated messages")
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
