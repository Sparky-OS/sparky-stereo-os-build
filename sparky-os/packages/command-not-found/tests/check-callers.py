#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/03
# Copyright 2026 under the GNU GPL3 License
# Judges callers-in-container.sh's probes: red (today's packages) must show the defect, green (the candidates) the renamed
# package first with the literal ones after it, and every command without a renamed package must be unchanged.
# Usage: check-callers.py OUT CANDIDATES; prints one line per check and exits 1 on any failure.
import json, re, sys
from pathlib import Path

out = Path(sys.argv[1])
red, green = out / 'red', out / 'green'
table = {}
for line in open('/usr/share/command-not-found/renamed-commands'):
    if line.strip() and not line.lstrip().startswith('#'):
        command, package, name = line.split()
        table[command] = (package, name)
failures = 0


def check(ok, what):
    global failures
    print('%s  %s' % ('PASS' if ok else 'FAIL', what))
    failures += not ok


def block(text):
    # command-not-found's lines: from its first "Command '" line to its last install line
    # a pty session adds carriage returns and the terminal's escape sequences around the shell's own output
    text = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[=>()][0-9A-Za-z]?', '', text).replace('\r', '')
    lines = [l.rstrip() for l in text.splitlines()]
    start = next((i for i, l in enumerate(lines) if l.startswith("Command '")), None)
    if start is None:
        return []
    end = max([i for i, l in enumerate(lines) if 'apt install' in l] + [start])
    return lines[start:end + 1]


def packages(lines):
    return [m.group(1) for l in lines for m in [re.search(r'apt install ([a-z0-9][a-z0-9.+-]*)', l)] if m]


check(table.get('fd') == ('fd-find', 'fdfind') and table.get('bat') == ('bat', 'batcat'), 'the installed table has fd and bat')
want = {
    'fd': ["Command 'fd' not found, but can be installed with:",
           "sudo apt install fd-find  # run it as 'fdfind'",
           "sudo apt install fdclone"],
    'bat': ["Command 'bat' not found, but can be installed with:",
            "sudo apt install bat                # run it as 'batcat'",
            "sudo apt install bacula-console-qt"],
}
literal = {'fd': 'fdclone', 'bat': 'bacula-console-qt'}
unchanged = ['cmatrix', 'docker', 'ts', 'wakeonlan', 'python']
for shell in ('bash', 'zsh', 'fish'):
    for c in ('fd', 'bat'):
        r = block((red / f'{shell}-{c}.txt').read_text())
        g = block((green / f'{shell}-{c}.txt').read_text())
        check(packages(r)[:1] == [literal[c]], f'red   {shell} {c}: today offers {packages(r)}')
        check(g == want[c], f'green {shell} {c}: {g}')
    for c in unchanged:
        same = (red / f'{shell}-{c}.txt').read_text() == (green / f'{shell}-{c}.txt').read_text()
        check(same and block((red / f'{shell}-{c}.txt').read_text()) != [], f'same  {shell} {c} (no renamed package)')

kr, kg = json.loads((red / 'krunner.json').read_text()), json.loads((green / 'krunner.json').read_text())
# today's runner takes commands of three letters or more: `fd` gets no match, `bat` bacula-console-qt
krunner_red = {'fd': [], 'bat': ['install:bacula-console-qt']}
for c in ('fd', 'bat'):
    ids_r = [m[0] for m in kr[c]]
    ids_g = [m[0] for m in kg[c]]
    rel = [m[2] for m in kg[c]]
    check(ids_r == krunner_red[c], f'red   KRunner {c}: {ids_r}')
    check(ids_g == ['install:' + table[c][0], 'install:' + literal[c]] and rel == sorted(rel, reverse=True) and rel[0] > rel[1]
          and kg[c][0][3] == want[c][1] and kg[c][1][3] == want[c][2] and kg[c][0][1] == want[c][0].rstrip(':'),
          f'green KRunner {c}: {[(m[0], m[2], m[3]) for m in kg[c]]}')
# the real KRunner library: only the missing program runner is installed, so its matches are the whole result
qr, qg = json.loads((red / 'krunner-real.json').read_text()), json.loads((green / 'krunner-real.json').read_text())
mine = lambda ms: [m for m in ms if m[0] == 'sparky-stereo-missing-program']
check(all(mine(qr[c]) == [] for c in qr), f'red   real KRunner: no match for any command (the runner is not enabled): {[c for c in qr if mine(qr[c])]}')
for c in ('fd', 'bat'):
    g = mine(qg[c])
    check([m[3] for m in g] == want[c][1:] and [m[2] for m in g] == [want[c][0].rstrip(':')] * 2 and g[0][4] > g[1][4],
          f'green real KRunner {c}: {[(m[1], m[3], m[4]) for m in g]}')
for c, ids in (('cmatrix', ['cmatrix']), ('docker', []), ('ts', ['moreutils']), ('wakeonlan', ['wakeonlan']), ('python', [])):
    g = mine(qg[c])
    check([m[3].split()[-1] for m in g] == ids, f'green real KRunner {c}: {[m[3] for m in g]}')
for sh in ('bash', 'zsh', 'fish'):
    for c in ('fd', 'bat'):
        r = block((red / f'pty-{sh}-{c}.txt').read_text())
        g = block((green / f'pty-{sh}-{c}.txt').read_text())
        check(packages(r)[:1] == [literal[c]] and g == want[c], f'pty   {sh} {c}: {packages(r)} then {packages(g)}')
    r, g = block((red / f'pty-{sh}-cmatrix.txt').read_text()), block((green / f'pty-{sh}-cmatrix.txt').read_text())
    check(r == g and packages(g) == ['cmatrix'], f'pty   {sh} cmatrix unchanged: {packages(g)}')

for c in unchanged:
    if c == 'ts':
        # two letters: no match today; now command-not-found's one package, as for longer commands
        check([m[0] for m in kr[c]] == [] and [m[0] for m in kg[c]] == ['install:moreutils'], f'two-letter KRunner ts: {[m[0] for m in kr[c]]} then {[m[0] for m in kg[c]]}')
    else:
        check(kr[c] == kg[c], f'same  KRunner {c}: {[m[0] for m in kg[c]]}')

for c in ('fd', 'bat'):
    r = (red / f'dolphin-{c}.txt').read_text().splitlines()
    g = (green / f'dolphin-{c}.txt').read_text().splitlines()
    check(bool(r) and f'--yes-label Install {literal[c]} ' in r[0], f'red   Dolphin {c}: {r[:1]}')
    check(bool(g) and f'--yes-label Install {table[c][0]} ' in g[0] and all(l in (green / f"dolphin-{c}.txt").read_text() for l in want[c]),
          f'green Dolphin {c}: {g[:1]}')
for c in ('cmatrix', 'docker', 'ts', 'wakeonlan'):
    same = (red / f'dolphin-{c}.txt').read_text() == (green / f'dolphin-{c}.txt').read_text()
    check(same, f'same  Dolphin {c}: {(green / f"dolphin-{c}.txt").read_text().splitlines()[:1]}')

said = {
    'en': "run it as 'fdfind'", 'pl': "uruchom jako 'fdfind'", 'pt_BR': "execute-o como 'fdfind'",
    'fr': 'exécutez-la sous le nom « fdfind »', 'de': 'als »fdfind« aufrufen', 'ja': "'fdfind' として実行してください",
    'ko': "'fdfind'(으)로 실행하십시오", 'zh_CN': '以 “fdfind” 运行', 'zh_TW': "以 'fdfind' 執行",
}
for lang, words in said.items():
    text = (green / f'lang-{lang}.txt').read_text()
    check(f'fd-find  # {words}' in text and 'fdclone' in text, f'green {lang}: {words}')

def cases(path):
    return {m.group(1): m.group(2) for m in re.finditer(r'^=== (.*)\n((?:(?!=== ).*\n)*)', path.read_text(), re.M)}
sr, sg = cases(red / 'sample-out.txt'), cases(green / 'sample-out.txt')
diff = [c for c in sr if c not in table and sr[c] != sg.get(c)]
check(len(sr) > 300 and set(sr) == set(sg) and not diff,
      f'same  {len([c for c in sr if c not in table])} sampled commands and words without a renamed package (different: {diff[:10]})')
print('%d failing checks' % failures)
sys.exit(1 if failures else 0)
