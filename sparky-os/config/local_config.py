"""Read the local settings (build.conf.example documents every key) for the Python tools.

    import local_config as cfg
    work = cfg.path('SPARKY_MIGRATION_WORK')
    host = cfg.get('SPARKY_A10_HOST')

A variable already set in the environment wins over the file. A missing key stops the
tool with the key's name and the file to add it to.
"""
import os
from pathlib import Path
import re

TREE = Path(__file__).resolve().parents[2]
CONFIG = Path(os.environ.get('SPARKY_STEREO_CONFIG',
                             Path.home() / '.config' / 'sparky-stereo' / 'build.conf'))
_KEY = re.compile(r'^[A-Za-z0-9_]+$')


def _expand(value, known):
    if value.startswith('~/'):
        value = str(Path.home()) + value[1:]
    value = value.replace('$HOME', str(Path.home()))
    return re.sub(r'\$\{([A-Za-z0-9_]+)\}', lambda m: known.get(m.group(1), ''), value)


def _load():
    values = {}
    if CONFIG.is_file():
        for line in CONFIG.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            key, value = line.split('=', 1)
            if not _KEY.match(key):
                continue
            values[key] = _expand(value.strip().strip('"'), {**values, **os.environ})
    values.update({k: v for k, v in os.environ.items() if k.startswith('SPARKY_')})
    if 'SPARKY_SYNC_TARGET' not in values and 'SPARKY_SYNC_HOST' in values and 'SPARKY_SYNC_PATH' in values:
        values['SPARKY_SYNC_TARGET'] = values['SPARKY_SYNC_HOST'] + ':' + values['SPARKY_SYNC_PATH']
    return values


VALUES = _load()


def get(key):
    value = VALUES.get(key)
    if not value:
        raise SystemExit(f'{key} is not set: add it to {CONFIG} '
                         f'(see {TREE / "sparky-os/config/build.conf.example"})')
    return value


def path(key):
    return Path(get(key))
