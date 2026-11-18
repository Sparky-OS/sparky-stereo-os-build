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

# The verifier's own place on the running system (never under --root): dpkg's native caller walks / usr usr/lib
# usr/lib/dpkg-stereo conffile-verify (src/main/archives.c leancode_verifier_open: root-owned, no group or other
# write, folders on the way, an executable file at the end), and the verifier then walks the lean library tree the same
# way (conffile-verify, library_trusted). Both answer exit 14 when a step fails. TREE_BASE lets a test put the whole
# walk under a folder of its own.
TREE = '/usr/lib/dpkg-stereo'
TREE_BASE = ''
FINDING_KEYS = {'mode': 'LOCAL86', 'owner': 'LOCAL87', 'type': 'LOCAL88', 'missing': 'LOCAL89', 'exec': 'LOCAL90'}


def _walk(root):
    """ROOT's entries, folders and files, ROOT first, in a fixed order (os.walk, so the hook never imports pathlib)."""
    found = [root]
    for here, dirs, files in os.walk(root):
        dirs.sort()
        found += [os.path.join(here, name) for name in dirs + sorted(files)]
    return found


def _trust_step(path, real, last=False):
    """Why REAL (the path as named to the person is PATH) fails the check, as [KEY, ARG...], or None."""
    try:
        info = os.lstat(real)
    except FileNotFoundError:
        return [FINDING_KEYS['missing'], path]
    except OSError:
        return [FINDING_KEYS['type'], path]
    if not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
        return [FINDING_KEYS['type'], path]
    if info.st_uid != 0:
        return [FINDING_KEYS['owner'], path, info.st_uid]
    if info.st_mode & 0o022:
        return [FINDING_KEYS['mode'], path, '%o' % (info.st_mode & 0o7777)]
    if last and not (stat.S_ISREG(info.st_mode) and info.st_mode & 0o111):
        return [FINDING_KEYS['exec'], path, '%o' % (info.st_mode & 0o7777)]
    return None


def trust_findings(limit=8):
    """Every step of the verifier's trust walk that fails now, as [KEY, ARG...] messages, in the order the callers
    meet them (at most LIMIT)."""
    found = []
    chain = ['/', '/usr', '/usr/lib', TREE, TREE + '/conffile-verify']
    for n, path in enumerate(chain):
        step = _trust_step(path, TREE_BASE + path, last=n == len(chain) - 1)
        if step:
            found.append(step)
            if step[0] == FINDING_KEYS['missing']:
                return found
    for path in [p[len(TREE_BASE):] for p in _walk(TREE_BASE + TREE + '/lean')]:
        step = _trust_step(path, TREE_BASE + path)
        if step:
            found.append(step)
        if len(found) >= limit:
            break
    return found[:limit]


def mend_own_tree():
    """The mode an early package left. Every entry under dpkg-stereo's own folder that root owns and that its group or
    others can write loses that write permission; nothing outside the folder is touched, and an entry that another
    user owns or that is a link is left as it is for trust_findings to name. Returns [(path, old, new)]."""
    mended = []
    for entry in _walk(TREE_BASE + TREE):
        try:
            info = os.lstat(entry)
            if stat.S_ISLNK(info.st_mode) or info.st_uid != 0 or not info.st_mode & 0o022:
                continue
            new = info.st_mode & 0o7777 & ~0o022
            os.chmod(entry, new)
            mended.append((entry[len(TREE_BASE):], '%o' % (info.st_mode & 0o7777), '%o' % new))
        except OSError:
            continue
    return mended


def reason_argument(item):
    """The reason of a kept item as a message argument: for a refusal of the verifier's trust, the step that failed
    when it was kept (which path, which check), else the general sentence."""
    return item.get('finding') or [REASONS[item['reason']]]


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
        if refresh and P.root == '' and os.geteuid() == 0 and any(i['reason'] == 14 for i in items.values()):
            # the one thing repair changes: dpkg-stereo's own folder, back to what the verifier trusts (a conffile never)
            for path, old, new in mend_own_tree():
                api.say('LOCAL92', [path, old, new])
        if refresh:
            # Repair rechecks: it never merges or replaces a person's file. A file is settled when it is its package's
            # own bytes, or the exact projection of the package's own original (what the post-invoke makes of a
            # conffile dpkg installed while the verifier was refused)
            for key, item in list(items.items()):
                try:
                    with open(P.real(item['path']), 'rb') as source:
                        current = source.read()
                    expected = conf.get(item['package'], {}).get(item['path'])
                    if expected and api.md5(current) == expected:
                        del items[key]
                    elif expected:
                        original = api.pristine_by_md5(P, {expected}).get(expected)
                        if original is not None and api.conffile_projection.projection_matches(
                                item['path'], original, current, item['package'])[0] == 'ok':
                            del items[key]
                except OSError:
                    pass
        findings = trust_findings() if any(i['reason'] == 14 for i in items.values()) else []
        details = []
        for item in items.values():
            item.pop('finding', None)
            if item['reason'] == 14 and findings:
                item['finding'] = findings[0]
            item['location'] = destination(P, item['path'], api, conf.get(item['package'], {}))
            args = [item['package'], item['path'], reason_argument(item), item['location']]
            details.append(api.text('LOCAL63', args, 'en'))
            api.say('LOCAL63', args)
        if items:
            kept = api.keep_problem(P, 'conffiles', ['LOCAL62', len(items)],
                                    detail='\n'.join(details), items=list(items.values()),
                                    repair=api.text('LOCAL91' if findings else 'LOCAL73'))
        else:
            kept = api.clear_problem(P, 'conffiles')
        if refresh:
            # what repair cannot mend is said even when every conffile is settled, because the next upgrade meets it
            # again; the verifier's place is the running system's, even for --root (conffile-verifier.md)
            for finding in trust_findings():
                api.say(finding[0], finding[1:])
        if kept and stream:
            stream.seek(0)
            stream.truncate()
        return kept and not items
    finally:
        if stream:
            stream.close()
