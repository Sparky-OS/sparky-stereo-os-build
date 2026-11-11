#!/usr/bin/env python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later
"""Require complete installer catalogues before lrelease can fall back to source text."""
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

REQUIRED = ('en', 'pl', 'pt_BR', 'fr', 'de', 'es', 'ja', 'ko', 'zh_CN', 'zh_TW')


def messages(path):
    tree = ET.parse(path).getroot()
    result = set()
    for context in tree.findall('context'):
        for message in context.findall('message'):
            translation = message.find('translation')
            if translation is None or translation.get('type') in ('unfinished', 'vanished', 'obsolete'):
                raise ValueError(f'{path}: unfinished or missing translation: {message.findtext("source")}')
            forms = translation.findall('numerusform') or [translation]
            if any(not ''.join(form.itertext()).strip() for form in forms):
                raise ValueError(f'{path}: empty translation: {message.findtext("source")}')
            key = (context.findtext('name'), message.findtext('source'), message.findtext('comment'))
            if key in result:
                raise ValueError(f'{path}: duplicate message: {key}')
            result.add(key)
    if not result:
        raise ValueError(f'{path}: empty catalogue')
    return result


def main(directory):
    directory = Path(directory)
    source = messages(directory / 'calamares-sparky_en.ts')
    for language in REQUIRED:
        path = directory / f'calamares-sparky_{language}.ts'
        translated = messages(path)
        if translated != source:
            raise ValueError(f'{path}: message coverage differs from English; missing={source-translated}, extra={translated-source}')
    for path in directory.glob('calamares-sparky_*.ts'):
        messages(path)


if __name__ == '__main__':
    try:
        main(sys.argv[1])
    except (OSError, ValueError, ET.ParseError) as error:
        sys.exit(f'Required installer translation could not be built: {error}. Repair the catalogue and rebuild.')
