#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/01
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/01
"""The boot's problems, kept until they are repaired (sparky-stereo-boot).

A step of the boot's upkeep that cannot do what it is for (update-grub, the boot images, the Secure Boot certificate
on the EFI system partition, the kernel cleanup, the 3D splash's handover, GRUB's resolution and font) says what
failed, why and what to do, in the system's language, and keeps it in /var/lib/sparky-stereo-boot/problems/STEP.json
with the command, its exit status and the end of its output: the evidence for the repair. The same step clears the
record when it next succeeds. `sparky-stereo-boot status` lists the records, `sparky-stereo-boot repair` runs again
what each one names, and each record is shown as a notification in the person's session (sparky-stereo-boot notify).

  problems.py run STEP KEY [ARG...] -- COMMAND...   runs COMMAND with its output shown; a failure is said and kept
                                                    (KEY's first two %s are COMMAND and its exit status, then ARGs),
                                                    a success clears STEP; exits with COMMAND's status
  problems.py record STEP KEY [ARG...] [--repair COMMAND...]
                                                    says and keeps a problem the caller found
  problems.py clear STEP                            the step succeeded
  problems.py say KEY [ARG...]                      says a notice, kept nowhere

An ARG of the form @LOCALn is that message itself, in the same language; from Python an ARG can also be a list
[KEY, ARG...], that message with its own arguments. Messages are the package's language files
(LOCALn="text", %s for the arguments). Environment, for tests: SPARKY_STEREO_ROOT prefixes /var/lib, and
SPARKY_STEREO_LANG_DIR names the language files' folder.
"""
import collections
import datetime
import json
import os
import subprocess
import sys

ROOT = os.environ.get('SPARKY_STEREO_ROOT', '')
DIR = ROOT + '/var/lib/sparky-stereo-boot/problems'
LANG_DIR = os.environ.get('SPARKY_STEREO_LANG_DIR', '/usr/share/sparky/sparky-stereo-boot')
LANGS = ('en', 'pl', 'pt_BR', 'fr', 'de', 'ja', 'ko', 'zh_CN', 'zh_TW')
TAG = 'sparky-stereo-boot'
OUTPUT_LINES = 200


def language():
    """The system's language among the nine: LANG, else /etc/default/locale; the whole name, then the bare language,
    then English; Chinese keeps its territory, zh_CN when none is named."""
    lang = os.environ.get('LANG', '')
    if not lang:
        try:
            for line in open(ROOT + '/etc/default/locale', encoding='utf-8'):
                if line.startswith('LANG='):
                    lang = line.split('=', 1)[1].strip().strip('"')
        except OSError:
            pass
    lang = lang.split('.')[0].split('@')[0]
    for code in ([lang, 'zh_CN'] if lang.startswith('zh') else [lang, lang.split('_')[0]]):
        if code in LANGS:
            return code
    return 'en'


_strings = {}


def strings(lang):
    if lang not in _strings:
        values = {}
        try:
            for line in open(os.path.join(LANG_DIR, lang), encoding='utf-8'):
                line = line.strip()
                if '=' in line and not line.startswith('#'):
                    key, value = line.split('=', 1)
                    values[key.strip()] = value.strip().strip('"')
        except OSError:
            pass
        _strings[lang] = values
    return _strings[lang]


def text(key, args=(), lang=None):
    """KEY in LANG (the system's language when None), its %s filled with ARGS; an @LOCALn argument is that message.
    A key missing from the language's file is taken from the English file and named, never left out."""
    lang = lang or language()
    template = strings(lang).get(key) or strings('en').get(key)
    filled = [text(a[0], a[1:], lang) if isinstance(a, (list, tuple)) and a
              else text(a[1:], (), lang) if isinstance(a, str) and a.startswith('@LOCAL') else str(a) for a in args]
    if template is None:
        return '%s %s' % (key, ' '.join(filled))
    try:
        return template % tuple(filled)
    except (TypeError, ValueError):
        return '%s %s' % (template, ' '.join(filled))


def say(key, args=()):
    """Says KEY on stderr in the system's language, and in English too when that is another, for support."""
    lang = language()
    print('%s: %s' % (TAG, text(key, args, lang)), file=sys.stderr, flush=True)
    if lang != 'en':
        print('%s: (en) %s' % (TAG, text(key, args, 'en')), file=sys.stderr, flush=True)


def path(step):
    return os.path.join(DIR, step + '.json')


def record(step, key, args=(), command=None, status=None, output='', repair=None, quiet=False):
    """Says the problem (unless QUIET) and keeps it. REPAIR is the list of commands that do the step again."""
    if not quiet:
        say(key, args)
    entry = {'step': step, 'time': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
             'key': key, 'args': [[str(x) for x in a] if isinstance(a, (list, tuple)) else str(a) for a in args],
             'command': command, 'status': status,
             'output': output, 'repair': repair or []}
    try:
        os.makedirs(DIR, mode=0o755, exist_ok=True)
        tmp = path(step) + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump(entry, f, indent=1, ensure_ascii=False)
            f.write('\n')
        os.chmod(tmp, 0o644)
        os.replace(tmp, path(step))
    except OSError as error:
        # the record is the evidence the repair needs: that it could not be kept is said too
        print('%s: %s: %s' % (TAG, path(step), error), file=sys.stderr, flush=True)
        return False
    return True


def clear(step):
    try:
        os.remove(path(step))
    except FileNotFoundError:
        pass
    except OSError as error:
        print('%s: %s: %s' % (TAG, path(step), error), file=sys.stderr, flush=True)
        return False
    return True


def pending():
    """The kept records, oldest first."""
    found = []
    try:
        names = sorted(n for n in os.listdir(DIR) if n.endswith('.json'))
    except FileNotFoundError:
        return []
    for name in names:
        try:
            with open(os.path.join(DIR, name), encoding='utf-8') as f:
                entry = json.load(f)
        except (OSError, ValueError) as error:
            entry = {'step': name[:-5], 'time': '', 'key': '', 'args': [], 'unreadable': str(error), 'repair': []}
        entry['file'] = os.path.join(DIR, name)
        found.append(entry)
    return sorted(found, key=lambda e: e.get('time', ''))


def message(entry, lang=None):
    if entry.get('unreadable'):
        return '%s: %s' % (entry['file'], entry['unreadable'])
    return text(entry.get('key', ''), entry.get('args', []), lang)


def execute(command):
    """Runs COMMAND with its output shown on stderr as it comes; returns its exit status and the end of its output."""
    tail = collections.deque(maxlen=OUTPUT_LINES)
    try:
        proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except OSError as error:
        line = '%s: %s' % (command[0], error)
        print(line, file=sys.stderr, flush=True)
        return 127, line + '\n'
    for raw in proc.stdout:
        line = raw.decode('utf-8', errors='replace')
        sys.stderr.write(line)
        sys.stderr.flush()
        tail.append(line)
    return proc.wait(), ''.join(tail)


def run(step, key, args, command, repair=None):
    status, output = execute(command)
    if status == 0:
        clear(step)
        return 0
    record(step, key, [' '.join(command), status] + list(args), command=command, status=status, output=output,
           repair=repair or [command])
    return status


def main(argv):
    if len(argv) >= 5 and argv[0] == 'run' and '--' in argv:
        cut = argv.index('--')
        if cut >= 3 and cut + 1 < len(argv):
            return run(argv[1], argv[2], argv[3:cut], argv[cut + 1:])
    if len(argv) >= 3 and argv[0] == 'record':
        args, repair = argv[3:], None
        if '--repair' in args:
            cut = args.index('--repair')
            args, repair = args[:cut], [args[cut + 1:]] if args[cut + 1:] else None
        return 0 if record(argv[1], argv[2], args, repair=repair) else 1
    if len(argv) == 2 and argv[0] == 'clear':
        return 0 if clear(argv[1]) else 1
    if len(argv) >= 2 and argv[0] == 'say':
        say(argv[1], argv[2:])
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
