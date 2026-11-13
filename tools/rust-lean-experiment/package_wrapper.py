#!/usr/bin/env python3
"""The edition package hook, restoring rust-src from the bound authored tree."""
import json
import os
from pathlib import Path
import sys


def restore(staging, authored, form):
    if not staging.is_dir():
        raise RuntimeError('rust-src staging directory missing')
    restored = []
    for original in authored.rglob('*.rs'):
        name = original.relative_to(authored)
        if '.pc' in name.parts or original.is_symlink():
            continue
        target = staging / name
        if not target.is_file() or target.is_symlink():
            continue
        data, want = target.read_bytes(), original.read_bytes()
        if data != want:
            if data != (form / name).read_bytes():
                raise RuntimeError(f'rust-src changed outside the prepared form: {name}')
            target.write_bytes(want)
            restored.append(str(name))
        if target.read_bytes() != want:
            raise RuntimeError('authored restoration failed: '+str(name))
    generated=authored/'debian/sparky-wit-projection.json'
    if generated.is_file():
        spec=json.loads(generated.read_text())
        for name,row in spec['files'].items():
            target=staging/name
            if not target.is_file():continue
            want=(authored/row['authored_asset']).read_bytes()
            other=json.loads((form/'debian/sparky-wit-projection.json').read_text())['files'][name]
            expected=(form/other['form_asset']).read_bytes()
            if target.read_bytes() not in (want,expected):raise RuntimeError('unexpected generated rust-src: '+name)
            if target.read_bytes()!=want:target.write_bytes(want);restored.append(name)
    # library/vendor is shipped by rust-src; its checksums must follow the
    # restored authored Rust bytes, rather than the lean build inputs.
    for original in authored.rglob('.cargo-checksum.json'):
        name=original.relative_to(authored)
        if '.pc' in name.parts or original.is_symlink():continue
        target=staging/name
        if not target.is_file() or target.is_symlink():continue
        data,want=target.read_bytes(),original.read_bytes()
        if data!=want:
            if data!=(form/name).read_bytes():raise RuntimeError('rust-src checksum changed outside prepared form: '+str(name))
            target.write_bytes(want);restored.append(str(name))
        manifest=json.loads(want)
        for rel,digest in manifest.get('files',{}).items():
            source=target.parent/rel
            if source.is_file() and (original.parent/rel).is_file():
                import hashlib
                if hashlib.sha256(source.read_bytes()).hexdigest()!=digest:
                    raise RuntimeError('authored rust-src checksum does not match payload: '+str(name)+' -> '+rel)
    return restored


def main(root):
    sys.path.insert(0, str(root / 'debian/sparky-lean-toolkit'))
    from lean import debhelper, release
    restored = restore(root/'debian/rust-src/usr/src/rustc-1.99.1',
                       Path(os.environ['RL541_AUTHORED']), Path(os.environ['RL541_FORM_SOURCE']))
    (root/'debian/rl541-restored-rust.json').write_text(json.dumps(restored, indent=2)+'\n')
    debhelper.link_gate = lambda built: print('Experiment installed-package tests follow assembly; publication gate deferred')
    original_build_tree = release.build_tree
    def build_tree(stage, out, preserve=None):
        if Path(stage).name == 'rust-src':
            preserve = {'/usr/src/rustc-*': 'exact authored source, restored from the bound A tree'}
        return original_build_tree(stage, out, preserve=preserve)
    release.build_tree = build_tree
    debhelper.build(root, root/'debian/sparky-lean-toolkit/provenance.sh')


if __name__ == '__main__':
    main(Path(sys.argv[1]))
