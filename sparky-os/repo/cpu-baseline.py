#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/17
# Copyright 2026 under the GNU GPL3 License
"""Fails when an amd64 program or library holds instructions the first 64-bit processors do not have.

The edition's amd64 packages run on every 64-bit PC (Debian's amd64 baseline: SSE2, no SSE3 and nothing later). A
compiler that is not told its target builds for the processor of the machine it runs on: Zig does (ORDER 658: the
problems engine built on a Ryzen died of an illegal instruction on an Ivy Bridge MacBook, and with it every program
that loads it). A recipe whose compiler can do that runs this on what it built.

Usage: cpu-baseline.py FILE...      exit 0: baseline only; 1: instructions above it (the first of each are listed);
                                    2: a file could not be read. Needs objdump (binutils).
"`rep bsf` is what objdump prints as tzcnt: on a processor without BMI it runs as bsf, and compilers emit it for the
baseline on purpose, so tzcnt passes here; lzcnt does not (it would run as bsr and count from the other end)."
"""
import re
import subprocess
import sys

GPR = (r'popcnt|lzcnt|movbe|crc32|andn|bextr|blsi|blsmsk|blsr|bzhi|mulx|pdep|pext|rorx|sarx|shlx|shrx|adcx|adox|'
       r'rdrand|rdseed|cmpxchg16b')
SSE = (r'addsubp[sd]|haddp[sd]|hsubp[sd]|lddqu|movddup|movshdup|movsldup|fisttp[sl]?l?|'
       r'pshufb|phadd[wd]|phaddsw|phsub[wd]|phsubsw|pmaddubsw|pmulhrsw|psign[bwd]|pabs[bwd]|palignr|'
       r'blendv?p[sd]|pblendvb|pblendw|dpp[sd]|extractps|insertps|movntdqa|mpsadbw|packusdw|pcmpeqq|pextr[bdq]|'
       r'pinsr[bdq]|pmaxs[bd]|pmaxu[wd]|pmins[bd]|pminu[wd]|pmov[sz]x[bwd][wdq]|pmuldq|pmulld|ptest|'
       r'round[ps][sd]|phminposuw|pcmpgtq|pcmp[ei]str[im]|aes[a-z0-9]+|pclmul[a-z]*qdq|sha(1|256)[a-z0-9]+|'
       r'xsave[a-z0-9]*|xrstor[a-z0-9]*')
ABOVE = re.compile(r'^(?:v(?!err$|erw$)[a-z0-9]+|(?:%s)[bwlq]?|%s)$' % (GPR, SSE))
WIDE = re.compile(r'%[yz]mm\d')
LINE = re.compile(r'^\s*([0-9a-f]+):\t([a-z][a-z0-9]*(?: [a-z][a-z0-9]*)?)\s*(.*)$')
PREFIX = {'lock', 'rep', 'repz', 'repnz', 'repe', 'repne', 'data16', 'addr32', 'notrack', 'bnd', 'cs', 'ds', 'es',
          'fs', 'gs', 'ss', 'rex', 'xacquire', 'xrelease'}


def above(path):
	"""The instructions above the baseline in one file: [(address, text)], or None when objdump cannot read it."""
	run = subprocess.run(['objdump', '-d', '--no-show-raw-insn', path], capture_output=True, text=True, errors='replace')
	if run.returncode != 0:
		sys.stderr.write(run.stderr)
		return None
	found = []
	for line in run.stdout.splitlines():
		match = LINE.match(line)
		if not match:
			continue
		words = match.group(2).split()
		while len(words) > 1 and (words[0] in PREFIX or words[0].startswith('rex')):
			words.pop(0)
		if ABOVE.match(words[0]) or WIDE.search(match.group(3)):
			found.append((match.group(1), ' '.join(words) + ' ' + match.group(3).strip()))
	return found


def main(paths):
	if not paths:
		sys.stderr.write(__doc__)
		return 2
	status = 0
	for path in paths:
		found = above(path)
		if found is None:
			status = 2
			continue
		if not found:
			print('%s: baseline only' % path)
			continue
		status = max(status, 1)
		kinds = {}
		for address, text in found:
			kinds.setdefault(text.split()[0], (address, text))
		sys.stderr.write('%s: %d instructions above the amd64 baseline, of %d kinds; the first of each:\n'
		                 % (path, len(found), len(kinds)))
		for name in sorted(kinds)[:20]:
			sys.stderr.write('  %s: %s\n' % kinds[name])
		sys.stderr.write('  The compiler was not told its target processor. For Zig: -mcpu=baseline (zig build: -Dcpu=baseline).\n')
	return status


if __name__ == '__main__':
	sys.exit(main(sys.argv[1:]))
