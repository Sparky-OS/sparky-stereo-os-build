"""Check the Vibe pack's shell catalogue and its Dolphin action label."""

from collections import Counter
import json
from pathlib import Path
import re
from string import Formatter


PACK = Path(__file__).resolve().parents[1]
LANGUAGES = set("en pt_BR es fr de pl ja ko zh_CN zh_TW".split())
KEYS = {f"LOCAL{number}" for number in range(1, 14)}
ASSIGNMENT = re.compile(r'^(LOCAL[0-9]+)="([^"\\$`]+)"$')


def read_catalogue(path):
    values = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        match = ASSIGNMENT.fullmatch(line)
        if not match:
            raise ValueError(f"{path.name}:{number}: expected a literal LOCAL assignment")
        key, value = match.groups()
        if key in values or not value.strip():
            raise ValueError(f"{path.name}:{number}: duplicate key or empty value for {key}")
        values[key] = value
    if values.keys() != KEYS:
        raise ValueError(f"{path.name}: expected LOCAL1 through LOCAL13")
    return values


def placeholders(value):
    return Counter((field, spec, conversion)
                   for _, field, spec, conversion in Formatter().parse(value)
                   if field is not None)


def main():
    try:
        paths = {path.name: path for path in (PACK / "lang").iterdir()}
        if paths.keys() != LANGUAGES:
            raise ValueError("expected exactly the ten edition catalogues")
        metadata = json.loads((PACK / "pack.json").read_text(encoding="utf-8"))
        names = metadata["menus"][0]["actions"][0]["name"]
        if names.keys() != LANGUAGES:
            raise ValueError("expected the captions action label in the ten edition languages")
        english = read_catalogue(paths["en"])
        expected = {key: placeholders(value) for key, value in english.items()}
        for language, path in sorted(paths.items()):
            actual = english if language == "en" else read_catalogue(path)
            for key, value in actual.items():
                if placeholders(value) != expected[key]:
                    raise ValueError(f"{language} {key}: placeholders differ from English")
            if actual["LOCAL1"] != names[language]:
                raise ValueError(f"{language} LOCAL1: differs from the captions action label")
    except ValueError as error:
        raise SystemExit(str(error)) from error
    print(f"{len(paths)} Vibe catalogues, {len(paths) * len(KEYS)} values checked")


if __name__ == "__main__":
    main()
