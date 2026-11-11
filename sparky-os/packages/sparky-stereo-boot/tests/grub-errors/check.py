import re, sys
expected, case, log, shown = sys.argv[1:5]
text = re.sub(r'\x1b\[[0-9;?=]*[a-zA-Z]', '', open(log, errors='replace').read())
for line in open(expected):
    if line.startswith('#') or '|' not in line:
        continue
    name, messages, stops = [p.strip() for p in line.split('|')]
    if name != case:
        continue
    problems = []
    errors = [l for l in text.splitlines() if l.startswith('error:')]
    wanted = []
    if messages != '-':
        for item in messages.split(' ; '):
            n, pattern = item.split(' x ', 1)
            wanted.append((int(n), pattern))
    for n, pattern in wanted:
        got = sum(1 for l in errors if re.fullmatch(pattern, l))
        if got != n:
            problems.append('%d x %s, found %d' % (n, pattern, got))
    other = [l for l in errors if not any(re.fullmatch(p, l) for _, p in wanted)]
    if other:
        problems.append('unexpected: ' + ' | '.join(sorted(set(other))))
    stopped = 'Press any key to continue' in text
    if stopped != (stops == 'key'):
        problems.append('GRUB %s at "Press any key", expected %s' % ('stopped' if stopped else 'did not stop', 'to stop' if stops == 'key' else 'to boot on'))
    if 'Loading Linux' not in text and stops == 'go':
        problems.append('GRUB never reached the kernel')
    print(('FAIL %s (expectation of %s): ' % (shown, case) + '; '.join(problems)) if problems else 'ok   %s' % shown)
    sys.exit(1 if problems else 0)
sys.exit('no expectation for ' + case)
