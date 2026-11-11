#!/usr/bin/python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later
"""Real target apt and KDE debconf, in a fresh private KWin Wayland session.

corefonts-gui.py HELPER TARGET EVIDENCE CASE LANGUAGE
CASE: accept, refuse, close, failed-download.
Set WAYLAND_INPUT, KWIN_SCRIPT and KWIN_CAPTURE to the isolated rig tools.
Never connect this harness to a person's desktop. No Xvfb or terminal is used.
"""
import os
from pathlib import Path
import subprocess
import sys
import time

helper, target, evidence, choice, language = sys.argv[1:]
assert choice in ('accept', 'refuse', 'close', 'failed-download')
assert os.environ.get('QT_QPA_PLATFORM') == 'wayland'
out = Path(evidence)
out.mkdir(parents=True, exist_ok=True)
logfile = out / 'frontend.log'


def keys(*codes):
    subprocess.run([os.environ['WAYLAND_INPUT'], *map(str, codes)], check=True)


def capture(name):
    with (out / (name + '-capture.txt')).open('w') as metadata:
        subprocess.run(['python3', os.environ['KWIN_CAPTURE'], str(out / (name + '.png'))],
                       stdout=metadata, stderr=subprocess.STDOUT, check=True)


with logfile.open('w') as log:
    process = subprocess.Popen([helper, '--window', target], stdout=log, stderr=subprocess.STDOUT,
                               env=dict(os.environ, INSTALLER_LANG=language))
    deadline = time.monotonic() + 420
    answered = notice = outcome = False
    notes = 0
    try:
        while process.poll() is None and time.monotonic() < deadline:
            text = logfile.read_text()
            if 'shared download notice state=' in text and not notice:
                time.sleep(0.6)
                capture('download-notice')
                # The warning defaults to Decline. Move to Continue explicitly.
                keys(105, 28)
                notice = True
            if 'KDE debconf EULA' in text and not answered:
                assert 'platform= "wayland" accepted= false' in text, text[-2000:]
                assert not (Path(target) / 'usr/share/fonts/truetype/msttcorefonts/Arial.ttf').exists()
                time.sleep(0.6)
                capture('licence')
                if choice == 'close':
                    subprocess.run(['python3', os.environ['KWIN_SCRIPT'], '/dev/null',
                                    'workspace.activeWindow.closeWindow();'], check=True)
                elif choice in ('accept', 'failed-download'):
                    keys(15, 28)  # Decline has focus; Tab selects Accept.
                else:
                    keys(28)      # Explicitly submit the false default.
                answered = True
            count = text.count('KDE debconf note')
            if count > notes:
                time.sleep(0.4)
                capture('debconf-note-' + str(count))
                keys(28)
                notes = count
            if 'outcome window shown' in text and not outcome:
                time.sleep(0.4)
                capture('outcome')
                keys(28)
                outcome = True
            time.sleep(0.1)
        status = process.wait(timeout=5)
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
assert answered, 'the KDE EULA was never presented'
assert logfile.read_text().count('KDE debconf EULA') == 1, 'licence question repeated'
fonts = list((Path(target) / 'usr/share/fonts/truetype/msttcorefonts').glob('*.ttf'))
if choice == 'accept':
    assert status == 0 and fonts, (status, len(fonts))
    family = subprocess.check_output(['chroot', target, 'fc-match', '-f', '%{family}', 'Arial'], text=True)
    assert family == 'Arial', family
    assert subprocess.check_output(['chroot', target, 'dpkg-query', '-W', '-f', '${Status}',
                                    'ttf-mscorefonts-installer'], text=True) == 'install ok installed'
    (out / 'fc-match.txt').write_text(family + '\n')
else:
    assert not fonts and outcome, (len(fonts), outcome)
    assert status == (0 if choice in ('refuse', 'close') else 1), status
answer = subprocess.check_output(['chroot', target, 'debconf-communicate', 'ttf-mscorefonts-installer'],
                                 input='GET msttcorefonts/accepted-mscorefonts-eula\n', text=True)
assert answer.strip() == ('0 true' if choice in ('accept', 'failed-download') else '0 false'), answer
(out / 'debconf-answer.txt').write_text(answer)
print(f'PASS private KWin Wayland {language} {choice}: exit={status}, fonts={len(fonts)}, notice={notice}')
