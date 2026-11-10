#!/usr/bin/env python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later
"""Validate and embed all nine catalogues; postrm cannot read removed package files."""
from pathlib import Path
import re
import shlex
import sys

LANGUAGES = ('en', 'pl', 'pt_BR', 'fr', 'de', 'es', 'ja', 'ko', 'zh_CN', 'zh_TW')
ARGUMENTS = {1: 1, 2: 1, 21: 2, 56: 2, 57: 0}


def generate(directory):
    cases = []
    for language in LANGUAGES:
        path = Path(directory) / language
        messages = {}
        for line in path.read_text().splitlines():
            if not line.strip() or line.startswith('#'):
                continue
            match = re.fullmatch(r'LOCAL(\d+)="(.+)"', line)
            if not match or int(match[1]) in messages:
                raise ValueError(f'{path}: malformed or duplicate message: {line}')
            messages[int(match[1])] = match[2]
        # the ones the maintainer scripts embed; the others (LOCAL3, the engine's title) are the catalogs' only
        if not ARGUMENTS.keys() <= messages.keys():
            raise ValueError(f'{path}: required message keys are {sorted(ARGUMENTS)}')
        cases.append(f'\t{language}) case $1 in')
        for key, count in ARGUMENTS.items():
            message = messages[key]
            if message.count('%s') != count or '%' in message.replace('%s', ''):
                raise ValueError(f'{path}: wrong format arguments in LOCAL{key}')
            cases.append(f'\t\t{key}) f={shlex.quote(message)} ;;')
        cases.append('\tesac ;;')
    # Nothing is emitted until every required catalogue has passed validation.
    print('say() {\n\tcase $lang in')
    print('\n'.join(cases))
    print('''\tesac
\tk=$1; shift
\tprintf "sparky-stereo-grub-l10n: $f\\n" "$@" >&2
\tif [ "$lang" != en ]; then lang_was=$lang; lang=en; say "$k" "$@"; lang=$lang_was; fi
}
lang=${LANG:-}
[ -n "$lang" ] || lang=$(sed -n 's/^LANG=//p' /etc/default/locale 2>/dev/null | tr -d '"' | head -n 1)
lang=${lang%%.*}
lang=${lang%%@*}
case $lang in
pt_BR|zh_CN|zh_TW) ;;
zh*) lang=zh_CN ;;
*) lang=${lang%%_*}; case $lang in pl|fr|de|es|ja|ko) ;; *) lang=en ;; esac ;;
esac
failure() {
\tif [ "$1" = configure ]; then say 21 update-grub "$2"; else
\t\tsay 56 update-grub "$2"
\t\tsay 57
\t\tprintf '%s\\n' "sudo dpkg --$1 sparky-stereo-grub-l10n" >&2
\tfi
\tsay 1 "$log"
}''')


if __name__ == '__main__':
    try:
        generate(sys.argv[1])
    except (OSError, ValueError) as error:
        sys.exit(f'Cannot embed required GRUB package messages: {error}. Repair the catalogue and rebuild.')
