#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/02
"""The services' problems, kept until they are repaired (sparky-stereo-service-defaults).

Nothing fails silently (Daniel, 2026-11-01: "either it works or not and the user must know"). A service whose default
this package sets that cannot start, or whose need cannot be determined, says what failed, why and what to do, in the
system's language, and keeps it in /var/lib/sparky-stereo-service-defaults/problems/UNIT.json with its exit status
and its own output: the evidence for the repair. The unit clears the record when it next starts. The same problem
found again keeps the time it was first found, so it is shown once. This is sparky-stereo-time's problems.py
(ORDER 346c), which follows sparky-stereo-boot's (ORDER 345).

  problems.py run STEP KEY [ARG...] [--repair COMMAND...] -- COMMAND...
                                     runs COMMAND with its output shown; a failure is said and kept (KEY's first two
                                     %s are COMMAND and its exit status, then ARGs), a success clears STEP; exits with
                                     COMMAND's status
  problems.py record STEP KEY [ARG...] [--repair COMMAND...]
                                     says and keeps a problem the caller found
  problems.py clear STEP...          the steps succeeded
  problems.py say KEY [ARG...]       says a notice, kept nowhere
  problems.py status                 lists the kept problems; exits 1 while one is kept
  problems.py repair                 root: runs again what each kept problem names
  problems.py dismiss STEP           root: the problem is not shown again until it changes or is repaired
  problems.py notify                 the session's side: each kept problem once as a desktop notification

An ARG of the form @LOCALn is that message itself, in the same language; from Python an ARG can also be a list
[KEY, ARG...], that message with its own arguments. Messages are the package's language files (LOCALn="text", %s for
the arguments). Environment, for tests: SPARKY_SERVICE_DEFAULTS_STATE names /var/lib/sparky-stereo-service-defaults,
SPARKY_SERVICE_DEFAULTS_LANGDIR the language files' folder.
"""
import collections
import datetime
import json
import os
import subprocess
import sys
import tempfile

STATE = os.environ.get('SPARKY_SERVICE_DEFAULTS_STATE', '/var/lib/sparky-stereo-service-defaults')
DIR = os.path.join(STATE, 'problems')
LANG_DIR = os.environ.get('SPARKY_SERVICE_DEFAULTS_LANGDIR', '/usr/share/sparky/sparky-stereo-service-defaults')
LANGS = ('en', 'pl', 'pt_BR', 'fr', 'de', 'ja', 'ko', 'zh_CN', 'zh_TW')
TAG = 'sparky-stereo-service-defaults'
OUTPUT_LINES = 200
# the messages of status, repair, dismiss and notify (lang/en)
HEADER, NONE, SINCE, EVIDENCE, DISMISSED, TITLE, FOOTER, REPAIRED, FAILED_AGAIN, HIDDEN, UNKNOWN = (
    'LOCAL8', 'LOCAL9', 'LOCAL10', 'LOCAL11', 'LOCAL12', 'LOCAL13', 'LOCAL14', 'LOCAL15', 'LOCAL16', 'LOCAL17',
    'LOCAL18')


def language():
    """The system's language among the nine: LANG, else /etc/default/locale; the whole name, then the bare language,
    then English; Chinese keeps its territory, zh_CN when none is named."""
    lang = os.environ.get('LANG', '')
    if lang in ('', 'C', 'POSIX') or lang.startswith(('C.', 'POSIX.')):
        try:
            for line in open('/etc/default/locale', encoding='utf-8'):
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
    A key missing from the language's file is taken from the English file, and a key missing from both is named with
    its arguments, never left out."""
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


def load(step):
    try:
        with open(path(step), encoding='utf-8') as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def write(entry):
    try:
        os.makedirs(DIR, mode=0o755, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix='.' + entry['step'] + '.', dir=DIR)
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            json.dump(entry, f, indent=1, ensure_ascii=False)
            f.write('\n')
        os.chmod(tmp, 0o644)
        os.replace(tmp, path(entry['step']))
    except OSError as error:
        # the record is the evidence the repair needs: that it could not be kept is said too
        print('%s: %s: %s' % (TAG, path(entry['step']), error), file=sys.stderr, flush=True)
        return False
    return True


def record(step, key, args=(), command=None, status=None, output='', repair=None, quiet=False):
    """Says the problem (unless QUIET) and keeps it. REPAIR is the list of commands that do the step again. The same
    problem kept already keeps the time it was first found and whether it was dismissed, and gets the new evidence."""
    if not quiet:
        say(key, args)
    args = [[str(x) for x in a] if isinstance(a, (list, tuple)) else str(a) for a in args]
    now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    old = load(step)
    same = old is not None and old.get('key') == key and old.get('args') == args
    entry = {'step': step, 'time': old.get('time', now) if same else now, 'checked': now,
             'key': key, 'args': args, 'command': command, 'status': status,
             'output': output, 'repair': repair or [], 'dismissed': bool(same and old.get('dismissed'))}
    return write(entry)


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
    """The kept records, oldest first; one that cannot be read is listed with the reason."""
    found = []
    try:
        names = sorted(n for n in os.listdir(DIR) if n.endswith('.json'))
    except FileNotFoundError:
        return []
    except OSError as error:
        return [{'step': '-', 'time': '', 'unreadable': str(error), 'file': DIR, 'repair': []}]
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


def status():
    found = pending()
    if not found:
        print(text(NONE))
        return 0
    print('%s:' % text(HEADER))
    shown = 0
    for entry in found:
        print('- %s' % message(entry))
        print('  %s: %s%s' % (text(SINCE), entry.get('time') or '-',
                              ' (%s)' % text(DISMISSED) if entry.get('dismissed') else ''))
        if entry.get('output'):
            print('  %s: %s' % (text(EVIDENCE), entry['file']))
        shown += 0 if entry.get('dismissed') else 1
    return 1 if shown else 0


def repair():
    """Runs again what each kept problem names; a step that succeeds is cleared, one that fails again is kept with its
    new output. A unit that fails again keeps its own new record (sparky-stereo-service-problem@)."""
    found = pending()
    if not found:
        print(text(NONE))
        return 0
    left = 0
    for entry in found:
        if not os.path.exists(entry['file']):
            continue   # an earlier repair cleared it
        print(message(entry))
        steps = entry.get('repair') or []
        if not steps:
            left += 1
            continue
        for command in steps:
            code, output = execute(command)
            if code != 0:
                after = load(entry['step'])
                if after is None or after.get('checked') == entry.get('checked'):
                    record(entry['step'], entry['key'], entry['args'], command=command, status=code, output=output,
                           repair=steps, quiet=True)
                print(text(FAILED_AGAIN, [' '.join(command), code]))
                left += 1
                break
        else:
            after = load(entry['step'])
            if after is not None and after.get('checked') != entry.get('checked'):
                # the unit failed again and its failure handler kept the new record
                print(text(FAILED_AGAIN, [' '.join(steps[-1]), 0]))
                left += 1
                continue
            clear(entry['step'])
            print(text(REPAIRED, [entry['step']]))
    return 1 if left else 0


def dismiss(step):
    entry = load(step)
    if entry is None:
        print('%s: %s' % (text(UNKNOWN, [step]), ', '.join(e['step'] for e in pending()) or '-'))
        return 1
    entry['dismissed'] = True
    if not write(entry):
        return 1
    print(text(HIDDEN, [step]))
    return 0


def notify():
    """The session's side: each kept problem as a notification (org.freedesktop.Notifications, critical, so it stays
    until the person closes it), once per session and record; a dismissed one is not shown."""
    runtime = os.environ.get('XDG_RUNTIME_DIR', '')
    seen_file = os.path.join(runtime, TAG + '-notified') if runtime else ''
    try:
        seen = set(open(seen_file).read().split()) if seen_file else set()
    except OSError:
        seen = set()
    result = 0
    for entry in pending():
        ident = '%s@%s' % (entry['step'], entry.get('time', ''))
        if ident in seen or entry.get('dismissed'):
            continue
        body = '%s\n%s' % (message(entry), text(FOOTER))
        try:
            call = subprocess.run(['busctl', '--user', 'call', 'org.freedesktop.Notifications',
                                   '/org/freedesktop/Notifications', 'org.freedesktop.Notifications', 'Notify',
                                   'susssasa{sv}i', 'Sparky Stereo OS', '0', 'dialog-warning', text(TITLE), body,
                                   '0', '1', 'urgency', 'y', '2', '0'], capture_output=True, text=True, timeout=60)
            error = call.stderr.strip() if call.returncode else ''
        except (OSError, subprocess.SubprocessError) as e:
            error = str(e)
        if error:
            print('%s: the notification could not be shown (%s): %s' % (TAG, error, message(entry, 'en')),
                  file=sys.stderr, flush=True)
            result = 1
            continue
        seen.add(ident)
    if seen_file:
        try:
            with open(seen_file + '.new', 'w') as f:
                f.write('\n'.join(sorted(seen)) + '\n')
            os.replace(seen_file + '.new', seen_file)
        except OSError as error:
            print('%s: %s: %s' % (TAG, seen_file, error), file=sys.stderr, flush=True)
    return result


def split_repair(args):
    """The arguments before --repair, an @LOCALn:VALUE among them being that message with VALUE as its argument; the
    repair command after it."""
    repair_command = None
    if '--repair' in args:
        cut = args.index('--repair')
        args, repair_command = args[:cut], [args[cut + 1:]] if args[cut + 1:] else None
    args = [a[1:].split(':', 1) if a.startswith('@LOCAL') and ':' in a else a for a in args]
    return args, repair_command


def main(argv):
    if len(argv) >= 5 and argv[0] == 'run' and '--' in argv:
        cut = argv.index('--')
        if cut >= 3 and cut + 1 < len(argv):
            args, repair_command = split_repair(argv[3:cut])
            return run(argv[1], argv[2], args, argv[cut + 1:], repair_command)
    if len(argv) >= 3 and argv[0] == 'record':
        args, repair_command = split_repair(argv[3:])
        return 0 if record(argv[1], argv[2], args, repair=repair_command) else 1
    if len(argv) >= 2 and argv[0] == 'clear':
        return 0 if all([clear(step) for step in argv[1:]]) else 1
    if len(argv) >= 2 and argv[0] == 'say':
        say(argv[1], argv[2:])
        return 0
    if argv == ['status']:
        return status()
    if argv == ['repair']:
        return repair()
    if len(argv) == 2 and argv[0] == 'dismiss':
        return dismiss(argv[1])
    if argv == ['notify']:
        return notify()
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
