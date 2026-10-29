"""Literal direct preinst forms: real shell arguments and scratch dpkg oracle."""
import json
import os
from pathlib import Path
import subprocess

import pytest
from lean import archive, package
from lean.tests.test_archive_diversions import deb, pair, extract, preinst


def direct():
    return ('#!/bin/sh\n# Created by Paweł and Daniel\nset -e\n'
            'if [ "$1" = install ] || [ "$1" = upgrade ]; then\n'
            '  dpkg-divert --package wrapper --add --rename \\\n'
            '    --divert /usr/share/fixture/banner.original /usr/share/fixture/banner >/dev/null\n'
            'fi\nexit 0\n').encode()


@pytest.mark.parametrize('action', ['install', 'upgrade', 'abort-upgrade'])
@pytest.mark.parametrize('continued', [False, True])
def test_direct_real_shell_arguments(tmp_path, action, continued):
    script = direct() if continued else direct().replace(b' \\\n    ', b' ')
    _, new = pair(tmp_path, script=script)
    rows = archive.static_diversions(new, archive.control(new))
    assert len(rows) == 1
    # Only this stub can run; the complete recognized script has no other
    # external command. No real dpkg or maintainer operation executes here.
    stub = tmp_path / 'dpkg-divert'
    stub.write_text('#!/usr/bin/python3\nimport json,os,sys\n'
                    'open(os.environ["ARGUMENTS"],"w").write(json.dumps(sys.argv[1:]))\n')
    stub.chmod(0o755)
    actual = tmp_path / 'arguments.json'
    source = tmp_path / 'script'; source.write_bytes(script)
    result = subprocess.run(['/bin/sh', str(source), action],
                            env={'PATH':str(tmp_path), 'ARGUMENTS':str(actual), 'LC_ALL':'C'},
                            capture_output=True)
    assert result.returncode == 0
    if action == 'abort-upgrade':
        assert not actual.exists()
    else:
        row = rows[0]
        assert json.loads(actual.read_text()) == ['--package',row['owner'],'--add','--rename',
                                                 '--divert',row['target'],row['source']]


@pytest.mark.parametrize('reverse', [False, True])
def test_direct_actual_dpkg_payloads(tmp_path, reverse):
    old, new = pair(tmp_path, script=direct())
    oracle = tmp_path/'oracle'; oracle.mkdir();(oracle/'var/lib/dpkg').mkdir(parents=True)
    subprocess.run(['dpkg-deb','-x',str(old),str(oracle)],check=True)
    subprocess.run(['dpkg-divert','--root',str(oracle),'--package','wrapper','--add','--rename',
                    '--divert','/usr/share/fixture/banner.original','/usr/share/fixture/banner'],
                   env={'PATH':'/usr/bin:/bin','LC_ALL':'C'},check=True,capture_output=True)
    subprocess.run(['dpkg-deb','-x',str(new),str(oracle)],check=True)
    root=tmp_path/'root';extract([new,old] if reverse else [old,new],root)
    for name in ['banner','banner.original']:
        assert (root/'usr/share/fixture'/name).read_bytes()==(oracle/'usr/share/fixture'/name).read_bytes()


@pytest.mark.parametrize('script',[
    direct().replace(b'--package', '—package'.encode()),
    direct().replace(b'--rename', '--rename\u00a0'.encode()),
    direct().replace(b'set -e', 'set -e\u2028'.encode()),
    direct().replace(b'\n', b'\r\n'),
    direct().replace(b'set -e', b'set -e\v'),
    direct().replace(b'set -e', b'set -e\f'),
    direct().replace(b'    --divert', b'    # hidden\n    --divert'),
    direct().replace(b'    --divert', b'\n    --divert'),
    direct().replace(b'    --divert', b'--divert'),
    direct().replace(b'# Created', b'# comment\\\n# Created'),
    direct().replace(b' \\\n', b'\\\n'),
    direct().replace(b' \\\n', b' \\ \n'),
    direct().replace(b'--divert ', b'--divert "').replace(b'.original ', b'.original" '),
    direct().replace(b'>/dev/null', b'>/tmp/output'),
    direct().replace(b'>/dev/null', b'>/dev/null; echo extra'),
    direct().replace(b'fi\n', b'echo extra\nfi\n'),
    direct().replace(b'exit 0', b'exit 0\necho extra'),
    direct().replace(b'--add', b'--remove'),
    direct().replace(b'--rename', b'--no-rename'),
    direct().replace(b'--package wrapper', b'--package other'),
    direct().replace(b'banner.original', b'../outside'),
    direct().replace(b'/usr/share/fixture/banner.original', b'//usr/share/fixture/banner.original'),
    direct().replace(b'/usr/share/fixture/banner.original', b'/usr//share/fixture/banner.original'),
    direct().replace(b'/usr/share/fixture/banner.original', b'$(echo /tmp/target)'),
    direct().replace(b'--add', b'--listpackage'),
])
def test_direct_ambiguous_or_dynamic_never_authorized(tmp_path, script):
    _,new=pair(tmp_path,script=script)
    with pytest.raises(package.Invalid):archive.static_diversions(new,archive.control(new))


def test_utf8_comment_preserves_existing_loop(tmp_path):
    _,new=pair(tmp_path,script=preinst().replace(b'set -e', '# Paweł 日本語 \u2028 stays a comment\nset -e'.encode()))
    assert len(archive.static_diversions(new,archive.control(new)))==1


@pytest.mark.parametrize('kind',['duplicate','target','chain','symlink'])
def test_direct_conflicts_still_rejected(tmp_path,kind):
    script=direct()
    if kind=='duplicate':script=script.replace(b'fi\n',script.split(b'then\n')[1].split(b'fi\n')[0]+b'fi\n')
    old,new=pair(tmp_path,script=script);paths=[old,new]
    if kind=='target':paths.append(deb(tmp_path,'third',files={'usr/share/fixture/banner.original':b'occupied'}))
    if kind=='chain':paths.append(deb(tmp_path,'second',files={'DEBIAN/preinst':direct().replace(b'wrapper',b'second').replace(b'banner.original',b'banner.last').replace(b'banner >',b'banner.original >')}))
    if kind=='symlink':paths.insert(0,deb(tmp_path,'parent',files={'usr/share/fixture':('/elsewhere',)}))
    with pytest.raises(package.Invalid):extract(paths,tmp_path/'root')
