# SPDX-License-Identifier: GPL-2.0-or-later
import hashlib
import json
import math
from pathlib import Path
import random

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def receipt(name, command, environment, proof, library):
    return dict(id=name, command=command, environment=environment, proof=proof,
                executable_sha256=digest(command[0]), library=str(Path(library).resolve()),
                library_sha256=digest(library))

def eligible(entry):
    try:
        proof = entry['proof']
        low, high = proof['disparity_bounds_px']
        minimum = -.02*proof['eye_width'] if proof.get('placement') == 'screen-level' else 0
        if (not all(math.isfinite(value) for value in (low,high,proof['eye_width'],proof['residual_px'])) or
                proof['passed'] is not True or not minimum <= low <= high <= .02*proof['eye_width'] or
                abs(proof['residual_px']) > 1 or not proof['oracle']):
            return False
        return (digest(entry['command'][0]) == entry['executable_sha256'] and
                digest(entry['library']) == entry['library_sha256'])
    except (OSError, KeyError, TypeError, ValueError):
        return False

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
            if not eligible(entry):
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
