# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""The problems engine (sparky-stereo-problems) for Python: the same calls as its C library.

    import sparky_stereo_problems as problems
    problems.keep('sparky-stereo-boot', 'update-grub', 'LOCAL3', ['update-grub', 1], repair=[['update-grub']])
    status = problems.run('sparky-stereo-boot', 'update-grub', 'LOCAL3', [], ['update-grub'])
    problems.clear('sparky-stereo-boot', 'update-grub')
    for p in problems.list(): print(p['title'], p['text'])

Each call raises problems.Failed with the reason in the person's language (and .english) when it fails.
"""
import builtins
import ctypes
import json
import os
import sys
import sysconfig

DEFAULT, MACHINE, BOOT, PERSON = -1, 0, 1, 2
_sequence = (builtins.list, tuple)
_lib = ctypes.CDLL('/usr/lib/%s/sparky-stereo-problems/libsparky-stereo-problems.so.0'
                   % (sysconfig.get_config_var('MULTIARCH') or 'x86_64-linux-gnu'))
_text = ctypes.POINTER(ctypes.c_char)
for _name, _res in (('ssp_keep', ctypes.c_int), ('ssp_run', ctypes.c_int), ('ssp_clear', ctypes.c_int),
                    ('ssp_say', ctypes.c_int), ('ssp_repair', ctypes.c_int), ('ssp_hide', ctypes.c_int),
                    ('ssp_show', ctypes.c_int), ('ssp_clear_all', ctypes.c_int), ('ssp_list_json', _text), ('ssp_render', _text),
                    ('ssp_message_id', _text), ('ssp_languages', _text), ('ssp_error', ctypes.c_char_p),
                    ('ssp_error_en', ctypes.c_char_p)):
    getattr(_lib, _name).restype = _res
_lib.ssp_free.argtypes = [ctypes.c_void_p]


class Failed(Exception):
    def __init__(self, text, english):
        super().__init__(text)
        self.english = english


def _b(s):
    return None if s is None else str(s).encode('utf-8')


def _list(items):
    items = [_b(x) for x in items]
    return (ctypes.c_char_p * max(len(items), 1))(*items), len(items)


def _check(status):
    if status != 0:
        raise Failed(_lib.ssp_error().decode('utf-8', 'replace'), _lib.ssp_error_en().decode('utf-8', 'replace'))


def _take(pointer):
    if not pointer:
        raise Failed(_lib.ssp_error().decode('utf-8', 'replace'), _lib.ssp_error_en().decode('utf-8', 'replace'))
    try:
        return ctypes.cast(pointer, ctypes.c_char_p).value.decode('utf-8')
    finally:
        _lib.ssp_free(pointer)


def _details(severity, command, status, output, repair, actions, unit, args, data=None, first=None, more=None):
    d = {k: v for k, v in (('severity', severity), ('command', command), ('status', status), ('output', output),
                           ('repair', repair), ('actions', actions), ('unit', unit), ('data', data),
                           ('first', first), ('more', more)) if v is not None}
    if any(isinstance(a, _sequence) for a in args):
        d['args'] = [[str(x) for x in a] if isinstance(a, _sequence) else str(a) for a in args]
    return _b(json.dumps(d)) if d else None


def keep(package, key, message, args=(), scope=DEFAULT, severity=None, command=None, status=None, output=None,
         repair=None, actions=None, unit=None, data=None, first=None, more=None):
    a, n = _list(x if not isinstance(x, _sequence) else '' for x in args)
    _check(_lib.ssp_keep(scope, _b(package), _b(key), _b(message), a, n,
                         _details(severity, command, status, output, repair, actions, unit, builtins.list(args),
                                  data, first, more)))


def run(package, key, message, args, command, scope=DEFAULT, severity=None, repair=None, actions=None, data=None):
    a, n = _list(x if not isinstance(x, _sequence) else '' for x in args)
    c, m = _list(command)
    status = _lib.ssp_run(scope, _b(package), _b(key), _b(message), a, n, c, m,
                          _details(severity, None, None, None, repair, actions, None, builtins.list(args), data))
    if status < 0:
        _check(1)
    return status


def clear(package, key, scope=DEFAULT):
    _check(_lib.ssp_clear(scope, _b(package), _b(key)))


def say(package, message, args=()):
    a, n = _list(args)
    _check(_lib.ssp_say(_b(package), _b(message), a, n))


def repair(package, key, scope=DEFAULT):
    status = _lib.ssp_repair(scope, _b(package), _b(key))
    if status < 0:
        _check(1)
    return status


def hide(package, key, scope=DEFAULT):
    _check(_lib.ssp_hide(scope, _b(package), _b(key)))


def show(package, key, scope=DEFAULT):
    _check(_lib.ssp_show(scope, _b(package), _b(key)))


def list(package=None, lang=None):  # noqa: A001 (the engine's own verb)
    return json.loads(_take(_lib.ssp_list_json(_b(package), _b(lang))))


def render(package, message, args=(), lang=None):
    a, n = _list(args)
    return json.loads(_take(_lib.ssp_render(_b(package), _b(message), a, n, _b(lang))))


def message_id(package, message):
    return _take(_lib.ssp_message_id(_b(package), _b(message)))


def languages():
    return [x for x in _take(_lib.ssp_languages()).split(':') if x]


def clear_all(package):
    """Every problem of PACKAGE goes from each store the caller can write (its postrm, when it is removed)."""
    _check(_lib.ssp_clear_all(_b(package)))


class Steps:
    """The steps of a package, kept until they are repaired, with the commands the edition's packages had before the
    one engine (ORDER 350): record, run, clear, say, pending, message, status, repair, dismiss and notify, and their
    command line. A STEP is the problem's key, a KEY (LOCALn) its message; the package's own words for status and
    repair are its messages named in WORDS (header, none, since, evidence, dismissed, repaired, failed_again, hidden,
    unknown, no_repair). Dismiss is the engine's Hide: the person's own, kept listed, back when the problem changes.
    """
    OUTPUT_LINES = 200

    def __init__(self, package, words=None, tag=None, scope=DEFAULT):
        self.package = package
        self.tag = tag or package
        self.words = dict(words or {})
        self.scope = scope

    @staticmethod
    def _args(args):
        return [[str(x) for x in a] if isinstance(a, _sequence) else str(a) for a in args]

    def language(self):
        langs = languages()
        return langs[0] if langs else 'en'

    def text(self, key, args=(), lang=None):
        """KEY in LANG (the person's languages when None), its %s filled with ARGS; an @LOCALn argument, or a list
        [KEY, ARG...], is that message itself."""
        args = [self.text(x[0], x[1:], lang) if isinstance(x, _sequence) else str(x) for x in args]
        return render(self.package, key, args, lang)['text']

    def say(self, key, args=()):
        """Says KEY on stderr in the person's language, and in English too when that is another, and in the
        journal; kept nowhere."""
        try:
            say(self.package, key, [self.text(x[0], x[1:]) if isinstance(x, _sequence) else str(x) for x in args])
        except Failed as error:
            self._failed(error)

    def _failed(self, error):
        print('%s: %s' % (self.tag, error), file=sys.stderr, flush=True)
        if error.english != str(error):
            print('%s: (en) %s' % (self.tag, error.english), file=sys.stderr, flush=True)

    def record(self, step, key, args=(), command=None, status=None, output='', repair=None, quiet=False, data=None,
               first=None):
        """Says the problem (unless QUIET) and keeps it; the same problem kept again keeps its first time and its
        hide. False, said, when it cannot be kept."""
        if not quiet:
            self.say(key, args)
        try:
            keep(self.package, step, key, args, scope=self.scope, command=command, status=status,
                 output=output or None, repair=repair or None, data=data, first=first)
        except Failed as error:
            self._failed(error)
            return False
        return True

    def clear(self, *steps):
        ok = True
        for step in steps:
            try:
                clear(self.package, step, scope=self.scope)
            except Failed as error:
                self._failed(error)
                ok = False
        return ok

    def pending(self):
        """The kept problems of the package, oldest first, as the older stores listed them; one that cannot be read
        is listed with the reason."""
        found = []
        for p in list(self.package):
            if 'unreadable' in p:
                found.append({'step': '-', 'time': '', 'unreadable': p['unreadable'], 'file': p['file'], 'repair': []})
                continue
            found.append({'step': p['key'], 'time': p['first'], 'checked': p['time'], 'key': p['message'],
                          'args': p['args'], 'command': p['command'], 'status': p['status'], 'output': p['output'],
                          'repair': p['repair'], 'dismissed': p['hidden'], 'file': p['file'], 'scope': p['scope'],
                          'text': p['text'], 'data': p.get('data')})
        return found

    def message(self, entry, lang=None):
        if entry.get('unreadable'):
            return '%s: %s' % (entry['file'], entry['unreadable'])
        if lang is None and 'text' in entry:
            return entry['text']
        return self.text(entry.get('key', ''), entry.get('args', []), lang)

    def execute(self, command):
        """Runs COMMAND with its output shown on stderr as it comes; its exit status and the end of its output."""
        import collections
        import subprocess
        tail = collections.deque(maxlen=self.OUTPUT_LINES)
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

    def run(self, step, key, args, command, repair=None):
        """Runs COMMAND with its output shown: a failure is said and kept (KEY's first two %s are COMMAND and its
        exit status, then ARGS), a success clears STEP; COMMAND's exit status."""
        try:
            status = run(self.package, step, key, self._args(args), command, scope=self.scope, repair=repair)
        except Failed as error:
            self._failed(error)
            return 1
        if status != 0:
            self.say(key, [' '.join(command), status] + builtins.list(args))
        return status

    def _word(self, name, args=()):
        key = self.words.get(name)
        return self.text(key, args) if key else ''

    def status(self):
        found = self.pending()
        if not found:
            print(self._word('none'))
            return 0
        print('%s:' % self._word('header'))
        shown = 0
        for entry in found:
            print('- %s' % self.message(entry))
            print('  %s: %s%s' % (self._word('since'), entry.get('time') or '-',
                                  ' (%s)' % self._word('dismissed') if entry.get('dismissed') and
                                  self.words.get('dismissed') else ''))
            if entry.get('output') and self.words.get('evidence'):
                print('  %s: %s' % (self._word('evidence'), entry['file']))
            shown += 0 if entry.get('dismissed') else 1
        return 1 if shown else 0

    def repair(self):
        """Runs again what each kept problem names, through the engine: one that succeeds goes, one that fails, or
        that its own command keeps again, stays with the new evidence."""
        found = self.pending()
        if not found:
            print(self._word('none'))
            return 0
        left = 0
        scopes = {'machine': MACHINE, 'boot': BOOT, 'person': PERSON}
        for entry in found:
            if entry.get('unreadable'):
                left += 1
                continue
            print(self.message(entry))
            if not entry.get('repair'):
                if self.words.get('no_repair'):
                    print(self._word('no_repair', [entry['step'], entry['step']]))
                left += 1
                continue
            try:
                code = repair(self.package, entry['step'], scope=scopes.get(entry['scope'], DEFAULT))
            except Failed as error:
                self._failed(error)
                left += 1
                continue
            if code == 0:
                print(self._word('repaired', [entry['step']]))
            else:
                after = [p for p in list(self.package) if p.get('key') == entry['step']]
                last = (after[0].get('last_repair') or {}) if after else {}
                print(self._word('failed_again', [' '.join(last.get('command') or entry['repair'][-1]),
                                                  last.get('status', code)]))
                left += 1
        return 1 if left else 0

    def dismiss(self, step):
        found = {e['step']: e for e in self.pending()}
        if step not in found:
            print('%s: %s' % (self._word('unknown', [step]) or step, ', '.join(sorted(found)) or '-'))
            return 1
        scopes = {'machine': MACHINE, 'boot': BOOT, 'person': PERSON}
        try:
            hide(self.package, step, scope=scopes.get(found[step]['scope'], DEFAULT))
        except Failed as error:
            self._failed(error)
            return 1
        print(self._word('hidden', [step]))
        return 0

    def notify(self):
        """The session's notifier (sparky-stereo-problems-plasma) shows every problem: this starts it."""
        import subprocess
        return subprocess.run(['systemctl', '--user', 'start', 'sparky-stereo-problems-notifier.service']).returncode

    def migrate(self, old_dir):
        """Moves the records of an older store (STEP.json: step, key, args, command, status, output, repair, time)
        into the engine, once, keeping when each was first found; the old store goes when every record moved."""
        try:
            names = sorted(n for n in os.listdir(old_dir) if n.endswith('.json'))
        except FileNotFoundError:
            return True
        except OSError as error:
            print('%s: %s: %s' % (self.tag, old_dir, error), file=sys.stderr, flush=True)
            return False
        ok = True
        for name in names:
            path = os.path.join(old_dir, name)
            try:
                with open(path, encoding='utf-8') as f:
                    e = json.load(f)
                step, key = e.get('step') or name[:-5], e['key']
            except (OSError, ValueError, KeyError) as error:
                print('%s: %s: %s' % (self.tag, path, error), file=sys.stderr, flush=True)
                ok = False
                continue
            if not self.record(step, key, e.get('args') or [], command=e.get('command'), status=e.get('status'),
                               output=e.get('output') or '', repair=e.get('repair') or None, quiet=True,
                               first=e.get('time') or None):
                ok = False
                continue
            os.remove(path)
        if ok:
            for rest in os.listdir(old_dir):
                os.remove(os.path.join(old_dir, rest))
            os.rmdir(old_dir)
        return ok

    @staticmethod
    def split_repair(args):
        """The arguments before --repair, an @LOCALn:VALUE among them being that message with VALUE as its argument;
        the repair command after it."""
        repair_command = None
        if '--repair' in args:
            cut = args.index('--repair')
            args, repair_command = args[:cut], [args[cut + 1:]] if args[cut + 1:] else None
        args = [a[1:].split(':', 1) if a.startswith('@LOCAL') and ':' in a else a for a in args]
        return args, repair_command

    def main(self, argv, doc=''):
        if len(argv) >= 5 and argv[0] == 'run' and '--' in argv:
            cut = argv.index('--')
            if cut >= 3 and cut + 1 < len(argv):
                args, repair_command = self.split_repair(argv[3:cut])
                return self.run(argv[1], argv[2], args, argv[cut + 1:], repair_command)
        if len(argv) >= 3 and argv[0] == 'record':
            args, repair_command = self.split_repair(argv[3:])
            return 0 if self.record(argv[1], argv[2], args, repair=repair_command) else 1
        if len(argv) >= 2 and argv[0] == 'clear':
            return 0 if self.clear(*argv[1:]) else 1
        if len(argv) >= 2 and argv[0] == 'say':
            self.say(argv[1], argv[2:])
            return 0
        if argv == ['status']:
            return self.status()
        if argv == ['repair']:
            return self.repair()
        if len(argv) == 2 and argv[0] == 'dismiss':
            return self.dismiss(argv[1])
        if argv == ['notify']:
            return self.notify()
        print(doc, file=sys.stderr)
        return 2
