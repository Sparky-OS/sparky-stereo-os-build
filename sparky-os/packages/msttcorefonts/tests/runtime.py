#!/usr/bin/python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later
"""Run one case in a fresh container with dependencies and the real ORDER 399 hook.

runtime.py CASE PACKAGE.deb EVIDENCE_DIR
CASE: accept, refuse, noninteractive, failed-download, retry-refusal, retry-download.
The retry cases use a container kept from the corresponding first case.
Only test mirror configuration is supplied; EULA acceptance is typed into debconf.
"""
import os
import gzip
from pathlib import Path
import shutil
import subprocess
import sys
import pexpect

case, package, evidence = sys.argv[1:]
out = Path(evidence)
out.mkdir(parents=True, exist_ok=True)
fonts = Path('/usr/share/fonts/truetype/msttcorefonts')

def mirror(value):
    subprocess.run(['debconf-communicate', 'ttf-mscorefonts-installer'],
                   input='SET msttcorefonts/dlurl ' + value + '\n', text=True, check=True,
                   stdout=subprocess.DEVNULL)

if case == 'failed-download':
    subprocess.run(['debconf-set-selections'], text=True, check=True,
                   input='ttf-mscorefonts-installer msttcorefonts/dlurl string https://127.0.0.1:9/\n')
elif case == 'retry-download':
    mirror('')

environment = dict(os.environ, LC_ALL='C.UTF-8', TERM='xterm', DEBIAN_FRONTEND='readline', DEBIAN_PRIORITY='critical')
if case in ('metered', 'unmetered'):
    # Only NetworkManager's answer is a stand-in; apt, its hook, metadata and consent gate are real.
    busctl = Path('/usr/local/bin/busctl')
    busctl.parent.mkdir(parents=True, exist_ok=True)
    busctl.write_text('#!/bin/sh\nprintf "u ' + ('1' if case == 'metered' else '2') + '\\n"\n')
    busctl.chmod(0o755)
    environment['PATH'] = '/usr/local/bin:/usr/bin:/bin'
if not case.startswith('retry-'):
    repo = Path('/tmp/fonts-519-repo')
    repo.mkdir(exist_ok=True)
    shutil.copyfile(package, repo / Path(package).name)
    with (repo / 'Packages').open('w') as index:
        subprocess.run(['dpkg-scanpackages', '.', '/dev/null'], cwd=repo, stdout=index, check=True)
    (repo / 'Packages.gz').write_bytes(gzip.compress((repo / 'Packages').read_bytes(), mtime=0))
    source = Path('/etc/apt/sources.list.d/fonts-519.list')
    source.write_text('deb [trusted=yes] file:/tmp/fonts-519-repo ./\n')
    subprocess.run(['apt-get', '-o', 'Dir::Etc::sourcelist=' + str(source), '-o', 'Dir::Etc::sourceparts=-',
                    '-o', 'APT::Get::List-Cleanup=false', 'update'], check=True, stdout=subprocess.DEVNULL)
    candidate = subprocess.check_output(['apt-cache', 'policy', 'ttf-mscorefonts-installer'], text=True)
    assert 'Candidate: 3.8.1+stereo3d1' in candidate, candidate
if case.startswith('retry-'):
    command = (['dpkg', '--configure', 'ttf-mscorefonts-installer'] if case == 'retry-download' else
               ['dpkg-reconfigure', 'ttf-mscorefonts-installer'])
else:
    announce = 'metered' if case in ('metered', 'unmetered') else 'always'
    command = ['apt-get', '--no-install-recommends', '-o', 'Dpkg::Use-Pty=0', '-o', 'Sparky::Install-Downloads::Announce=' + announce,
               'install', 'ttf-mscorefonts-installer']
if case in ('noninteractive', 'metered', 'unmetered'):
    environment['DEBIAN_FRONTEND'] = 'noninteractive'
    command.insert(1, '-y')

eula = question = notice = False
questions = 0
with (out / (case + '.log')).open('w') as log:
    child = pexpect.spawn(command[0], command[1:], env=environment, encoding='utf-8', timeout=300, dimensions=(50, 120))
    child.logfile_read = log
    while True:
        match = child.expect([r'END-USER LICENSE AGREEMENT', r'Do you accept the Microsoft EULA\? \[yes/no\]',
                              r'These packages download more data while they are installed:',
                              r'Do you want to continue\?[^\r\n]*', r'Press [Ee]nter[^\r\n]*',
                              r'\[More\]|--More--', pexpect.EOF])
        if match == 0:
            eula = True
        elif match == 1:
            question = True
            questions += 1
            child.sendcontrol('u')  # readline pre-fills the default "no".
            child.sendline('no' if case == 'refuse' else 'yes')
        elif match == 2:
            notice = True
        elif match == 3:
            child.sendline('y')
        elif match in (4, 5):
            child.sendline('')
        else:
            break
    child.close()
    status = child.exitstatus if child.exitstatus is not None else 128 + child.signalstatus
text = (out / (case + '.log')).read_text()
print(f'{case}: exit={status}, EULA={eula}, question={question}, shared-notice={notice}')
if case not in ('noninteractive', 'metered', 'unmetered', 'retry-download'):
    assert eula and question, 'the EULA and actual acceptance question must be presented'
    assert questions == 1, 'the same installation must not ask for consent twice'
if case == 'unmetered':
    assert not notice, 'unmetered install must not show the metered notice'
elif not case.startswith('retry-'):
    assert notice and '3.8 MiB' in text and 'https://downloads.sourceforge.net/corefonts/' in text, 'shared size/source notice missing'
if case in ('refuse', 'noninteractive', 'metered', 'unmetered', 'failed-download'):
    assert not list(fonts.glob('*.ttf')), 'fonts arrived without acceptance or despite a failed download'
    assert 'not installed' in text.lower(), 'missing visible outcome'
    assert 'dpkg-reconfigure ttf-mscorefonts-installer' in text, 'missing retry command'
    if case == 'failed-download':
        assert status != 0, 'failed download must fail the transaction'
        assert 'dpkg --configure ttf-mscorefonts-installer' in text
    else:
        assert status == 0, 'deliberate refusal must allow the OS installation to continue'
else:
    assert status == 0, text[-2000:]
    assert (fonts / 'Arial.ttf').is_file()
    result = subprocess.check_output(['fc-match', '-f', '%{family}\n', 'Arial'], text=True).strip()
    assert result == 'Arial', result
    package_state = subprocess.check_output(['dpkg-query', '-W', '-f', '${db:Status-Status}',
                                             'ttf-mscorefonts-installer'], text=True).strip()
    assert package_state == 'installed', 'retry left dpkg state: ' + package_state
    print(f'font files={len(list(fonts.glob("*.ttf")))}, fc-match Arial={result}')
print('PASS', case)
