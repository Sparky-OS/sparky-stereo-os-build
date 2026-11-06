"""The 157 real symptoms (data/routing/symptoms-157.tsv, from the skills review of 25 Oct to 6 Nov 2026) put to both engines.
For every symptom the Zig engine must give the same top three skills, in the same order and with scores equal to two
decimals, as the Python engine it replaces; the top-1 and top-3 hit rates against the expected skill are printed.
Usage: compare.py ENGINE PUBLIC_CHECKOUT ORACLE_SCRIPT SYMPTOMS.tsv"""
import re
import subprocess
import sys

engine, pub, oracle, table = sys.argv[1:5]
row = re.compile(r'^(\d+)\. (\S+) \(score ([0-9.]+)\)', re.M)


def ranked(argv):
    p = subprocess.run(argv, capture_output=True, text=True)
    return [(m[2], float(m[3])) for m in row.finditer(p.stdout)]


symptoms = []
for line in open(table, encoding='utf-8'):
    if line.startswith('#') or not line.strip():
        continue
    text, expect = line.rstrip('\n').split('\t')
    symptoms.append((text, expect))

different = []
top1 = top3 = 0
for text, expect in symptoms:
    old = ranked([sys.executable, '-I', oracle, '--find', text, '--limit', '3'])
    new = ranked([engine, '--root', pub, 'find', '--all', '--limit', '3', text])
    if [n for n, _ in old] != [n for n, _ in new] or any(abs(a[1] - b[1]) > 0.0051 for a, b in zip(old, new)):
        different.append((text, old, new))
    if new and new[0][0] == expect:
        top1 += 1
    if expect in [n for n, _ in new]:
        top3 += 1
n = len(symptoms)
print(f'{n} symptoms; top-1 {top1} ({100 * top1 // n}%), top-3 {top3} ({100 * top3 // n}%) against the expected skill (Zig engine)')
print(f'rankings that differ from the Python engine: {len(different)}')
for text, old, new in different[:10]:
    print('  ', text[:70], '\n     python', old, '\n     zig   ', new)
sys.exit(1 if different or n != 157 else 0)
