# SPDX-License-Identifier: GPL-2.0-or-later
import hashlib
import json
import math
from pathlib import Path
import random
import sys

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def receipt(name, command, environment, proof, library):
    return dict(id=name, command=command, environment=environment, proof=proof,
                executable_sha256=digest(command[0]), library=str(Path(library).resolve()),
                library_sha256=digest(library))

def _where(path, root):
    return Path(str(root)+str(path)) if root else Path(path)

def diagnose(entry, root=''):
    """Why a receipt cannot be offered: a list of reasons, empty when it can.

    Each reason names its kind, the file and, for a binary that differs, the hash the receipt
    names (expected) and the hash of the file found (found). ROOT is a folder the paths are
    read under (the publication gate reads a round's unpacked packages; the installed system
    uses none).
    """
    reasons = []
    try:
        proof = entry['proof']
        low, high = proof['disparity_bounds_px']
        minimum = -.02*proof['eye_width'] if proof.get('placement') == 'screen-level' else 0
        if (not all(math.isfinite(value) for value in (low,high,proof['eye_width'],proof['residual_px'])) or
                proof['passed'] is not True or not minimum <= low <= high <= .02*proof['eye_width'] or
                abs(proof['residual_px']) > 1 or not proof['oracle']):
            reasons.append(dict(kind='proof', path=None, expected=None, found=None))
    except (KeyError, TypeError, ValueError):
        reasons.append(dict(kind='proof', path=None, expected=None, found=None))
    for kind, key, path_of in (('executable', 'executable_sha256', lambda: entry['command'][0]),
                               ('library', 'library_sha256', lambda: entry['library'])):
        try:
            path, expected = path_of(), entry[key]
        except (KeyError, IndexError, TypeError):
            reasons.append(dict(kind=kind+'-unreadable', path=None, expected=None, found=None))
            continue
        try:
            found = digest(_where(path, root))
        except OSError:
            reasons.append(dict(kind=kind+'-missing', path=path, expected=expected, found=None))
            continue
        if found != expected:
            reasons.append(dict(kind=kind+'-differs', path=path, expected=expected, found=found))
    expected = entry.get('verification', {}).get('settings_sha256') if isinstance(entry.get('verification'), dict) else None
    if expected:
        path = '/usr/share/xscreensaver/config/%s.xml' % entry.get('id')
        try:
            found = digest(_where(path, root))
        except OSError:
            reasons.append(dict(kind='settings-missing', path=path, expected=expected, found=None))
        else:
            if found != expected:
                reasons.append(dict(kind='settings-differs', path=path, expected=expected, found=found))
    return reasons

def eligible(entry, root=''):
    return not diagnose(entry, root)

def describe(reason, short=False):
    """One English line for a log or a command; the saver list has its own translated texts."""
    cut = (lambda value: value[:12]) if short else (lambda value: value)
    kind, path = reason['kind'], reason['path']
    if kind == 'proof':
        return 'its receipt does not pass the proof gates'
    if kind.endswith('-differs'):
        return '%s %s differs: qualified %s, installed %s' % ({'settings': 'settings file'}.get(kind.split('-')[0], kind.split('-')[0]), path, cut(reason['expected']), cut(reason['found']))
    if kind.endswith('-missing'):
        return '%s %s is not installed (qualified %s)' % (kind.split('-')[0], path, cut(reason['expected']))
    return 'its receipt does not name a %s' % kind.split('-')[0]

def dropped(entries, root=''):
    """The receipts that cannot be offered, with their reasons: [(id, reasons)]."""
    result = []
    for entry in entries:
        reasons = diagnose(entry, root)
        if reasons:
            result.append((entry.get('id', '?'), reasons))
    return result

def load(path):
    # This is a trusted package-validation artifact, never saver-supplied data.
    entries = json.loads(Path(path).read_text())
    return [entry for entry in entries if eligible(entry)]

class Rotation:
    def __init__(self, entries, rng=None):
        self.entries = {entry['id']: entry for entry in entries if eligible(entry)}
        self.rng = rng or random.SystemRandom()
        self.bag = []
        self.last = None

    def exclude(self, name):
        self.entries.pop(name, None)
        self.bag = [item for item in self.bag if item != name]

    def next(self, disabled=()):
        for name, entry in list(self.entries.items()):
            reasons = diagnose(entry)
            if reasons:
                for reason in reasons:
                    print('gl-stereo-savers: %s is not offered any more: %s' % (name, describe(reason)), file=sys.stderr)
                self.exclude(name)
        available = {name for name in self.entries if name not in disabled}
        self.bag = [name for name in self.bag if name in available]
        if not available:
            return None
        if not self.bag:
            self.bag = list(available)
            self.rng.shuffle(self.bag)
            if len(self.bag) > 1 and self.bag[-1] == self.last:
                self.bag[-1], self.bag[0] = self.bag[0], self.bag[-1]
        self.last = self.bag.pop()
        return self.entries[self.last]

def active(state):
    return all(state.get(key) is True for key in ('locked','display_on','on_ac'))


def report(path, root='', log=sys.stderr):
    """Say, for the catalogue at PATH, which savers it cannot offer and why. Returns (offered, shipped)."""
    entries = json.loads(Path(path).read_text())
    gone = dropped(entries, root)
    for name, reasons in gone:
        for reason in reasons:
            print('gl-stereo-savers: %s is not offered: %s' % (name, describe(reason)), file=log)
    return len(entries)-len(gone), len(entries)

if __name__ == '__main__':
    # catalogue.py CATALOGUE [ROOT]: exit 1 when the catalogue would load fewer savers than it ships
    offered, shipped = report(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else '', sys.stdout)
    print('gl-stereo-savers: %d of %d savers can be offered' % (offered, shipped))
    sys.exit(0 if offered == shipped else 1)
