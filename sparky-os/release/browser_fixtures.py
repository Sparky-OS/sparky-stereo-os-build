"""Give local-file browser cases writable fixtures without editing originals."""
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg


def copy_media(out):
    source = (cfg.path('SPARKY_BROWSER_WORK') / 'media-m3')
    target = out / 'media'
    shutil.copytree(source, target, symlinks=True)
    records = []
    for original in sorted(source.rglob('*')):
        copied = target / original.relative_to(source)
        if original.is_symlink():
            assert copied.is_symlink() and copied.readlink() == original.readlink()
            continue
        if not original.is_file():
            continue
        raw = original.read_bytes()
        assert copied.read_bytes() == raw
        attrs = {name: os.getxattr(original, name) for name in os.listxattr(original)}
        assert {name: os.getxattr(copied, name) for name in os.listxattr(copied)} == attrs
        records.append(dict(path=str(original.relative_to(source)),
                            sha256=hashlib.sha256(raw).hexdigest(),
                            xattrs={name:base64.b64encode(value).decode() for name,value in attrs.items()}))
    (out / 'media-inputs.json').write_text(json.dumps(dict(
        original=str(source), writable_copy=str(target), files=records,
        purpose='Local-file cases create their HTML page beside synthetic media'), indent=2)+'\n')
    return target
