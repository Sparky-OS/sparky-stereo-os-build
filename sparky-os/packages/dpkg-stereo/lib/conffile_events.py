# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Drain dpkg's conffile decision journal into the edition's problems engine.

The journal is locked by native writers and this reader. It is truncated only
when the problems engine has kept the result; a failed hook can retry it later.
No conffile, candidate or pristine copy is written here.
"""

import fcntl
import os
import stat

REASONS = {10: 'LOCAL64', 11: 'LOCAL65', 12: 'LOCAL66', 13: 'LOCAL67',
           14: 'LOCAL68', 15: 'LOCAL69', 16: 'LOCAL70', 17: 'LOCAL71'}


def destination(P, path, api, originals):
    candidates = [path + suffix for suffix in ('.dpkg-dist', '.dpkg-new')
                  if os.path.lexists(P.real(path + suffix))]
    if candidates:
        return ', '.join(candidates)
    expected = originals.get(path)
    if expected:
        try:
            with open(P.real(path), 'rb') as stream:
                if api.md5(stream.read()) == expected:
                    return api.text('LOCAL74', [path])
        except OSError:
            pass
    return api.text('LOCAL75')


def report(P, api, refresh=False):
    name = P.state('conffile-events')
    try:
        fd = os.open(name, os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        if not refresh:
            return True
        fd = None
    if fd is not None:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o022:
            os.close(fd)
            raise ValueError('untrusted conffile decision journal')
        stream = os.fdopen(fd, 'r+b')
    else:
        stream = None
    try:
        if stream:
            fcntl.flock(stream, fcntl.LOCK_EX)
            data = stream.read()
            problem_file = P.root + '/var/lib/sparky-stereo-problems/dpkg-stereo_conffiles.json'
            if not data and not refresh and not os.path.exists(problem_file):
                return True
        else:
            data = b''
        previous = next((p for p in api.kept_problems(P) if p.get('step') == 'conffiles'), {})
        items = {(r['package'], r['path']): r for r in previous.get('items', [])}
        for row in data.splitlines():
            package, encoded, code = row.decode('ascii').split('\t')
            path = bytes.fromhex(encoded).decode('utf-8', 'surrogateescape')
            if not path.startswith('/') or '\0' in path:
                raise ValueError('invalid conffile decision path')
            reason = int(code)
            if reason == 0:
                items.pop((package, path), None)
            elif reason in REASONS:
                items[package, path] = dict(package=package, path=path, reason=reason)
            else:
                raise ValueError('unknown conffile decision reason')
        db = api.dpkg_db(P) if items else {}
        present = {n for n, _ in api._installed(P, db, api.INSTALLED_STATES +
                                              ('unpacked', 'half-installed', 'config-files'))}
        removed = {key for key in items if key[0] not in present}
        for key in removed:
            del items[key]
        if not data and not refresh and not removed:
            return not items
        conf = api.conffiles(P, db) if items else {}
        if refresh:
            # Repair only rechecks: it never merges or replaces a person's file.
            for key, item in list(items.items()):
                try:
                    with open(P.real(item['path']), 'rb') as source:
                        current = source.read()
                    expected = conf.get(item['package'], {}).get(item['path'])
                    if expected and api.md5(current) == expected:
                        del items[key]
                except OSError:
                    pass
        details = []
        for item in items.values():
            item['location'] = destination(P, item['path'], api, conf.get(item['package'], {}))
            args = [item['package'], item['path'], [REASONS[item['reason']]], item['location']]
            details.append(api.text('LOCAL63', args, 'en'))
            api.say('LOCAL63', args)
        if items:
            kept = api.keep_problem(P, 'conffiles', ['LOCAL62', len(items)],
                                    detail='\n'.join(details), items=list(items.values()),
                                    repair=api.text('LOCAL73'))
        else:
            kept = api.clear_problem(P, 'conffiles')
        if kept and stream:
            stream.seek(0)
            stream.truncate()
        return kept and not items
    finally:
        if stream:
            stream.close()
