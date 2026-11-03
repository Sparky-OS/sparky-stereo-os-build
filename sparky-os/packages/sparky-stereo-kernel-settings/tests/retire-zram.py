#!/usr/bin/python3
"""Exercise real maintscripts/engine with private proc/sys/state paths.

Usage: retire-zram.py PREINST POSTINST LANGDIR OUT. Run as root in a container.
Only paths into proc, sys and package migration state are relocated; no real
swap device is made, stopped or reset. Commands are failing/successful stubs.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

pre, post, lang, out = map(Path, sys.argv[1:])
out.mkdir(parents=True, exist_ok=True)
assert os.geteuid() == 0
engine = 'sparky-stereo-problems'
pkg = 'sparky-stereo-kernel-settings'
with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    root.chmod(0o755)
    catalog = root / 'catalog'
    subprocess.run([engine, 'catalog', pkg, str(lang), str(catalog), '--subject', 'LOCAL1'], check=True)
    paths = ['/var/lib/sparky-stereo-kernel-settings', '/usr/lib/systemd/zram-generator.conf.d',
             '/sys/block/zram0', '/proc/swaps', '/run/systemd/system']
    for name, original in [('preinst', pre), ('postinst', post)]:
        text = original.read_text()
        for path in paths:
            text = text.replace(path, td + path)
        (root / name).write_text(text)
    marker = root / 'var/lib/sparky-stereo-kernel-settings/retire-owned-zram0'
    config = root / 'usr/lib/systemd/zram-generator.conf.d/50-sparky-stereo.conf'
    config.parent.mkdir(parents=True)
    config.write_text('set!sparky_zram=/usr/libexec/sparky-stereo/zram-auto\n')
    swaps = root / 'proc/swaps'
    swaps.parent.mkdir()
    size = root / 'sys/block/zram0/disksize'
    size.parent.mkdir(parents=True)
    reset = size.with_name('reset')
    binpath = root / 'bin'
    binpath.mkdir()
    (binpath / 'swapoff').write_text('''#!/bin/sh
echo "$*" >>"$CALLS"
if [ "$FAIL" = yes ]; then echo 'injected swapoff failure' >&2; exit 7; fi
sed -i '\\|^/dev/zram0 |d' "$SWAPS"
''')
    (binpath / 'swapoff').chmod(0o755)
    env = dict(os.environ, PATH=f'{binpath}:/usr/bin:/bin', LC_ALL='C.UTF-8',
               SPARKY_STEREO_PROBLEMS_CATALOG=f'{catalog}:/usr/lib/systemd/catalog',
               CALLS=str(root/'calls'), SWAPS=str(swaps))
    for case in ['inactive', 'active', 'failure', 'repair', 'not-ours']:
        subprocess.run([engine, 'clear', '--all', pkg], env=env, check=True)
        marker.unlink(missing_ok=True)
        reset.unlink(missing_ok=True)
        (root / 'calls').unlink(missing_ok=True)
        if case == 'not-ours':
            config.write_text('[zram0]\nzram-size=1024\n')
        swaps.write_text('Filename Type Size Used Priority\n/swapfile file 8192 0 -2\n' +
                         ('/dev/zram0 partition 4096 0 100\n' if case != 'inactive' else ''))
        size.write_text('0\n' if case == 'inactive' else '4194304\n')
        subprocess.run(['sh', str(root/'preinst'), 'upgrade', '20261103.1'], env=env, check=True)
        result = subprocess.run(['sh', str(root/'postinst'), 'configure', '20261103.1'],
                                env=dict(env, FAIL='yes' if case in ['failure','repair'] else 'no'),
                                text=True, capture_output=True)
        (out/f'{case}.log').write_text(result.stdout+result.stderr)
        assert result.returncode == 0, result.stderr
        listed = subprocess.check_output([engine, 'list', '--json', pkg], env=env, text=True)
        (out/f'{case}.json').write_text(listed)
        records = json.loads(listed)
        assert '/swapfile file 8192 0 -2' in swaps.read_text()
        if case in ['failure','repair']:
            assert len(records) == 1 and records[0]['status'] == 7, listed
            assert 'injected swapoff failure' in result.stderr
            assert marker.exists() and not reset.exists()
            if case == 'repair':
                subprocess.run([engine, 'repair', '--machine', pkg, 'retire-zram'],
                               env=dict(env, FAIL='no'), check=True)
                assert json.loads(subprocess.check_output([engine, 'list', '--json', pkg], env=env)) == []
                assert not marker.exists() and reset.read_text() == '1\n'
        else:
            assert not records and not marker.exists()
            if case == 'active':
                assert '/dev/zram0' not in swaps.read_text() and reset.read_text() == '1\n'
                assert (root/'calls').read_text() == '/dev/zram0\n'
            else:
                assert not (root/'calls').exists() and not reset.exists()
        print('PASS', case, 'exit', result.returncode, 'other swap unchanged')
    subprocess.run([engine, 'clear', '--all', pkg], env=env, check=True)
