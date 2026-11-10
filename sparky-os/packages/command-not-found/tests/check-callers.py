#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Judges callers-in-container.sh's probes: red (today's packages) must show the defect, green (the candidates) each
# renamed package in its table order with the literal ones kept, every command without a renamed package unchanged, an
# installed renamed program said and run, and a table that cannot be read said in every caller.
# Usage: check-callers.py OUT CANDIDATES; prints one line per check and exits 1 on any failure.
import json, re, sys
from pathlib import Path

out = Path(sys.argv[1])
red, green, installed = out / 'red', out / 'green', out / 'installed'
TABLE = '/usr/share/command-not-found/renamed-commands'
table = {}
for line in open(TABLE):
    if line.strip() and not line.lstrip().startswith('#'):
        command, package, name, order = line.split()
        table[command] = (package, name, order)
failures = 0


def check(ok, what):
    global failures
    print('%s  %s' % ('PASS' if ok else 'FAIL', what))
    failures += not ok


def block(text):
    # command-not-found's lines: from its first "Command '" line to its last install or "is installed as" line
    # (a pty session adds carriage returns and the terminal's escape sequences around the shell's own output)
    text = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[=>()][0-9A-Za-z]?', '', text).replace('\r', '')
    lines = [l.rstrip() for l in text.splitlines()]
    start = next((i for i, l in enumerate(lines) if l.startswith("Command '") or l.startswith('The renamed-commands table')), None)
    if start is None:
        return []
    end = max([i for i, l in enumerate(lines) if 'apt install' in l or ' is installed as ' in l] + [start])
    return lines[start:end + 1]


def packages(lines):
    return [m.group(1) for l in lines for m in [re.search(r'apt install ([a-z0-9][a-z0-9.+-]*)', l)] if m]


def header(c):
    return "Command '%s' not found, but can be installed with:" % c


check(table.get('fd') == ('fd-find', 'fdfind', 'first') and table.get('ts') == ('task-spooler', 'tsp', 'after'),
      f'the installed table: {sorted(table)}')
want = {
    'fd': [header('fd'), "sudo apt install fd-find  # run it as 'fdfind'", 'sudo apt install fdclone'],
    'bat': [header('bat'), "sudo apt install bat                # run it as 'batcat'", 'sudo apt install bacula-console-qt'],
    'ts': [header('ts'), 'sudo apt install moreutils', "sudo apt install task-spooler  # run it as 'tsp'"],
    'cal': [header('cal'), 'sudo apt install ncal', "sudo apt install ccal  # run it as 'ccal'"],
}
literal = {'fd': 'fdclone', 'bat': 'bacula-console-qt', 'ts': 'moreutils', 'cal': 'ncal'}
unchanged = ['cmatrix', 'docker', 'wakeonlan', 'python']

for shell in ('bash', 'zsh', 'fish'):
    for c in want:
        r = block((red / f'{shell}-{c}.txt').read_text())
        g = block((green / f'{shell}-{c}.txt').read_text())
        check(packages(r) == [literal[c]], f'red   {shell} {c}: today offers {packages(r)}')
        check(g == want[c], f'green {shell} {c}: {g}')
    for c in unchanged:
        same = (red / f'{shell}-{c}.txt').read_text() == (green / f'{shell}-{c}.txt').read_text()
        check(same and block((red / f'{shell}-{c}.txt').read_text()) != [], f'same  {shell} {c} (no renamed package)')
    for c in ('fd', 'bat', 'ts', 'cal'):
        r = block((red / f'pty-{shell}-{c}.txt').read_text())
        g = block((green / f'pty-{shell}-{c}.txt').read_text())
        check(packages(r) == [literal[c]] and g == want[c], f'pty   {shell} {c}: {packages(r)} then {packages(g)}')
    r, g = block((red / f'pty-{shell}-cmatrix.txt').read_text()), block((green / f'pty-{shell}-cmatrix.txt').read_text())
    check(r == g and packages(g) == ['cmatrix'], f'pty   {shell} cmatrix unchanged: {packages(g)}')

mine = lambda ms: [m for m in ms if m[0] == 'sparky-stereo-missing-program']
qr, qg = json.loads((red / 'krunner-real.json').read_text()), json.loads((green / 'krunner-real.json').read_text())
dr, dg = json.loads((red / 'krunner-dbus.json').read_text()), json.loads((green / 'krunner-dbus.json').read_text())
check(all(mine(qr[c]) == [] for c in qr), f'red   real KRunner: no match for any command (the runner is not enabled): {[c for c in qr if mine(qr[c])]}')
# today's runner takes commands of three letters or more and matches only one package
dbus_red = {'fd': [], 'bat': ['install:bacula-console-qt'], 'ts': [], 'cal': ['install:ncal']}
for c in want:
    g = mine(qg[c])
    check([m[3] for m in g] == want[c][1:] and [m[2] for m in g] == [want[c][0].rstrip(':')] * 2 and g[0][4] > g[1][4],
          f'green real KRunner {c}: {[(m[1], m[3], m[4]) for m in g]}')
    check([m[0] for m in dr[c]] == dbus_red[c], f'red   D-Bus Match {c}: {[m[0] for m in dr[c]]}')
    check([m[3] for m in dg[c]] == want[c][1:] and dg[c][0][2] > dg[c][1][2], f'green D-Bus Match {c}: {[m[0] for m in dg[c]]}')
for c, ids in (('cmatrix', ['cmatrix']), ('docker', []), ('wakeonlan', ['wakeonlan']), ('python', [])):
    g = mine(qg[c])
    check([m[3].split()[-1] for m in g] == ids, f'green real KRunner {c}: {[m[3] for m in g]}')
    check(dr[c] == dg[c], f'same  D-Bus Match {c}: {[m[0] for m in dg[c]]}')

for c in want:
    r = (red / f'dolphin-{c}.txt').read_text()
    g = (green / f'dolphin-{c}.txt').read_text()
    offer = table[c][0] if table[c][2] == 'first' else literal[c]
    check(f'--yes-label Install {literal[c]} ' in r.splitlines()[0], f'red   Dolphin {c}: {r.splitlines()[:1]}')
    check(f'--yes-label Install {offer} ' in g.splitlines()[0] and all(l in g for l in want[c]), f'green Dolphin {c}: {g.splitlines()[:1]}')
for c in ('cmatrix', 'docker', 'wakeonlan'):
    same = (red / f'dolphin-{c}.txt').read_text() == (green / f'dolphin-{c}.txt').read_text()
    check(same, f'same  Dolphin {c}: {(green / f"dolphin-{c}.txt").read_text().splitlines()[:1]}')

said = {
    'en_US': ("run it as 'fdfind'", header('fd')),
    'pl_PL': ("uruchom jako 'fdfind'", None), 'pt_BR': ("execute-o como 'fdfind'", "Comando 'fd' não encontrado, mas pode ser instalado com:"),
    'fr_FR': ('exécutez-la sous le nom « fdfind »', None), 'de_DE': ('als »fdfind« aufrufen', None),
    'es_ES': ('ejecútela como «fdfind»', None),
    'ja_JP': ("'fdfind' として実行してください", None), 'ko_KR': ("'fdfind'(으)로 실행하십시오", None),
    'zh_CN': ('以 “fdfind” 运行', None), 'zh_TW': ("以 'fdfind' 執行", "找不到 'fd' 指令，但可以用以下方式安裝："),
}
for lang, (words, head) in said.items():
    text = (green / f'lang-{lang}.txt').read_text()
    first = text.splitlines()[0] if text else ''
    check(f'fd-find  # {words}' in text and 'fdclone' in text and (first == head if head else first != header('fd')),
          f'green {lang}: {first} / {words}')

# the renamed programs installed
for shell in ('bash', 'zsh', 'fish'):
    fd = block((installed / f'{shell}-fd.txt').read_text())
    ts = block((installed / f'{shell}-ts.txt').read_text())
    check(fd == ["Command 'fd' is installed as '/usr/bin/fdfind' from deb fd-find", header('fd'), 'sudo apt install fdclone'],
          f'installed {shell} fd: {fd}')
    check(ts == [header('ts'), 'sudo apt install moreutils', "Command 'ts' is installed as '/usr/bin/tsp' from deb task-spooler"],
          f'installed {shell} ts: {ts}')
qi = json.loads((installed / 'krunner-real.json').read_text())
fd, ts = mine(qi['fd -e txt']), mine(qi['ts'])
check([m[1].split('_', 1)[1] for m in fd] == ['run:/usr/bin/fdfind -e txt', 'install:fdclone'] and fd[0][2] == "Command 'fd' is installed as '/usr/bin/fdfind' from deb fd-find"
      and fd[0][3] == 'fdfind -e txt' and fd[0][4] > fd[1][4], f'installed real KRunner "fd -e txt": {[(m[1], m[2], m[3]) for m in fd]}')
check([m[1].split('_', 1)[1] for m in ts] == ['install:moreutils', 'run:/usr/bin/tsp'] and ts[0][4] > ts[1][4],
      f'installed real KRunner ts: {[(m[1], m[3]) for m in ts]}')
ran = (installed / 'konsole.log').read_text().splitlines()
check(ran == ['--noclose -e /usr/bin/fdfind -e txt'], f'installed real KRunner runs fdfind in the terminal: {ran}')

# the table cannot be read
for phase, error in (('missing', 'No such file or directory'), ('unreadable', 'Permission denied')):
    d = out / phase
    line = f'The renamed-commands table {TABLE} could not be read ({error}); reinstalling command-not-found restores it.'
    cnf = block((d / 'cnf-fd.txt').read_text())
    check(cnf == [line, header('fd'), 'sudo apt install fdclone'], f'{phase} command-not-found fd: {cnf}')
    for shell in ('bash', 'zsh', 'fish'):
        check(block((d / f'{shell}-fd.txt').read_text()) == cnf, f'{phase} {shell} fd: the same lines')
    q = json.loads((d / 'krunner-real.json').read_text())
    check([m[3] for m in mine(q['fd'])] == [line + ' sudo apt install fdclone'] and [m[3] for m in mine(q['cmatrix'])] == [line + ' sudo apt install cmatrix'],
          f'{phase} real KRunner: {[m[3] for m in mine(q["fd"]) + mine(q["cmatrix"])]}')
    firsts = {}
    for lang in said:
        text = (d / f'lang-{lang}.txt').read_text()
        firsts[lang] = text.splitlines()[0] if text else ''
    check(all(TABLE in f and 'command-not-found' in f for f in firsts.values()) and len(set(firsts.values())) == len(firsts),
          f'{phase} in nine languages: {firsts}')


def cases(path):
    return {m.group(1): m.group(2) for m in re.finditer(r'^=== (.*)\n((?:(?!=== ).*\n)*)', path.read_text(), re.M)}
sr, sg = cases(red / 'sample-out.txt'), cases(green / 'sample-out.txt')
diff = [c for c in sr if c not in table and sr[c] != sg.get(c)]
check(len(sr) > 300 and set(sr) == set(sg) and not diff,
      f'same  {len([c for c in sr if c not in table])} sampled commands and words without a renamed package (different: {diff[:10]})')
print('%d failing checks' % failures)
sys.exit(1 if failures else 0)
