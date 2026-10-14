# SPDX-License-Identifier: GPL-2.0-or-later
"""The show's saver selection is a Plasma session preference."""
import configparser
import os
from pathlib import Path
import tempfile

def config_path():
    return Path(os.environ.get('XDG_CONFIG_HOME',Path.home()/'.config'))/'stereoshowrc'

def read_config():
    config=configparser.ConfigParser(interpolation=None,strict=False)
    config.optionxform=str
    config.read(config_path())
    return config

def disabled_savers():
    value=read_config().get('General','DisabledSavers',fallback='')
    return {name.strip() for name in value.split(',') if name.strip()}

def save_disabled(names):
    if any(not name or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in name) for name in names):
        raise ValueError('invalid saver identifier')
    config=read_config()
    if not config.has_section('General'): config.add_section('General')
    config.set('General','DisabledSavers',','.join(sorted(set(names))))
    path=config_path(); path.parent.mkdir(parents=True,exist_ok=True)
    fd,temporary=tempfile.mkstemp(prefix='.stereoshow-',dir=path.parent)
    try:
        with os.fdopen(fd,'w') as out: config.write(out,space_around_delimiters=False)
        os.replace(temporary,path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
