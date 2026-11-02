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
import sysconfig

DEFAULT, MACHINE, BOOT, PERSON = -1, 0, 1, 2
_sequence = (builtins.list, tuple)
_lib = ctypes.CDLL('/usr/lib/%s/sparky-stereo-problems/libsparky-stereo-problems.so.0'
                   % (sysconfig.get_config_var('MULTIARCH') or 'x86_64-linux-gnu'))
_text = ctypes.POINTER(ctypes.c_char)
for _name, _res in (('ssp_keep', ctypes.c_int), ('ssp_run', ctypes.c_int), ('ssp_clear', ctypes.c_int),
                    ('ssp_say', ctypes.c_int), ('ssp_repair', ctypes.c_int), ('ssp_hide', ctypes.c_int),
                    ('ssp_show', ctypes.c_int), ('ssp_list_json', _text), ('ssp_render', _text),
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


def _details(severity, command, status, output, repair, actions, unit, args):
    d = {k: v for k, v in (('severity', severity), ('command', command), ('status', status), ('output', output),
                           ('repair', repair), ('actions', actions), ('unit', unit)) if v is not None}
    if any(isinstance(a, _sequence) for a in args):
        d['args'] = [[str(x) for x in a] if isinstance(a, _sequence) else str(a) for a in args]
    return _b(json.dumps(d)) if d else None


def keep(package, key, message, args=(), scope=DEFAULT, severity=None, command=None, status=None, output=None,
         repair=None, actions=None, unit=None):
    a, n = _list(x if not isinstance(x, _sequence) else '' for x in args)
    _check(_lib.ssp_keep(scope, _b(package), _b(key), _b(message), a, n,
                         _details(severity, command, status, output, repair, actions, unit, builtins.list(args))))


def run(package, key, message, args, command, scope=DEFAULT, severity=None, repair=None, actions=None):
    a, n = _list(args)
    c, m = _list(command)
    status = _lib.ssp_run(scope, _b(package), _b(key), _b(message), a, n, c, m,
                          _details(severity, None, None, None, repair, actions, None, []))
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
