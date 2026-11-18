#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/17
# Copyright 2026 under the GNU GPL3 License
"""Fails when an amd64 program or library holds instructions the first 64-bit processors do not have.

The edition's amd64 packages run on every 64-bit PC (Debian's amd64 baseline: SSE2, no SSE3 and nothing later). A
compiler that is not told its target builds for the processor of the machine it runs on: Zig does (ORDER 658: the
problems engine built on a Ryzen died of an illegal instruction on an Ivy Bridge MacBook, and with it every program
that loads it). A recipe whose compiler can do that runs this on what it built.

A Go program always holds newer instructions: the standard library and x/crypto carry AES-NI, AVX2, SHA-NI, CLMUL and POPCNT
code that the runtime chooses by CPUID, and GOAMD64=v1 (the default) makes the compiler emit its own POPCNT and ROUNDSD only
behind a test of the CPU-feature byte. So a Go program (an ELF with a .go.buildinfo section) is judged by what can be checked
statically, and the file is named by what it fails:
  1. its build setting must be GOAMD64=v1 (recorded in the build info; absent or v2 and up: fail, the compiler then emits
     the newer instructions unguarded everywhere);
  2. every instruction above the baseline must be in a function of the runtime-dispatched set (GO_DISPATCHED below: the
     standard library's and x/crypto's assembly, the runtime's own CPU-feature code) or be a compiler-guarded form (POPCNT,
     ROUNDSD/ROUNDSS or an FMA with a test of a feature byte just before it); function names are read from the program's own
     .gopclntab, so a program without one fails ("cannot be named").
What this does not prove: that the dispatching code tests CPUID correctly. The recipe's run on a baseline processor (qemu64)
is the proof of that; this check is the one that stays able to fail a Go program that really needs a newer processor.

Usage: cpu-baseline.py [-v] FILE...  exit 0: baseline only (or, for Go, as above); 1: instructions above it (the first of each are
                                    listed); 2: a file could not be read. Needs objdump (binutils). -v lists the Go functions
                                    that held newer instructions and why each is allowed.
"`rep bsf` is what objdump prints as tzcnt: on a processor without BMI it runs as bsf, and compilers emit it for the
baseline on purpose, so tzcnt passes here; lzcnt does not (it would run as bsr and count from the other end)."
"""
import re
import struct
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


# Go: package prefixes whose assembly or CPU-feature code chooses its path by CPUID at run time (internal/cpu), as of Go 1.27.
GO_DISPATCHED = ('crypto/', 'vendor/golang.org/x/crypto/', 'golang.org/x/crypto/', 'golang.org/x/image/vector.', 'hash/crc32.',
                 'math/big.', 'math.', 'internal/runtime/', 'internal/bytealg.', 'internal/chacha8rand.', 'internal/cpu.',
                 'runtime.', 'runtime/internal/', 'countbody', 'indexbody', 'cmpbody', 'memeqbody', 'indexbytebody')
GUARDED = {}   # path -> addresses of compiler-guarded instructions (a feature-byte test just before them)
GO_GUARDED = re.compile(r'^(popcnt|round[ps][sd]|vfn?m(add|sub)[0-9a-z]*[ps][sd])$')


def elf_sections(data):
	"""{name: (vaddr, file offset, size)} of a 64-bit little-endian ELF, or None."""
	if data[:4] != b'\x7fELF' or data[4] != 2 or data[5] != 1:
		return None
	shoff, = struct.unpack_from('<Q', data, 0x28)
	shentsize, shnum, shstrndx = struct.unpack_from('<HHH', data, 0x3A)
	raw = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * shentsize) for i in range(shnum)]
	names = raw[shstrndx]
	table = data[names[4]:names[4] + names[5]]
	out = {}
	for r in raw:
		end = table.index(b'\0', r[0])
		out[table[r[0]:end].decode()] = (r[3], r[4], r[5])
	return out


def go_functions(data, sections):
	"""[(address, name)] sorted, from .gopclntab (Go 1.20 and later layout); None when it cannot be read."""
	if '.gopclntab' not in sections or '.text' not in sections:
		return None
	_, off, size = sections['.gopclntab']
	pc = data[off:off + size]
	if len(pc) < 72 or struct.unpack_from('<I', pc, 0)[0] != 0xfffffff1 or pc[7] != 8:
		return None
	nfunc, nfiles = struct.unpack_from('<QQ', pc, 8)
	funcname_off, = struct.unpack_from('<Q', pc, 32)
	pcln_off, = struct.unpack_from('<Q', pc, 64)
	# textStart is a pointer: in the file itself for a fixed-address program; for a PIE it is filled by a relocation, and the one place
	# that shows it is runtime.firstmoduledata, whose first field points at .gopclntab and whose minpc (offset 160) and text (offset 176)
	# are the first function's address
	text = struct.unpack_from('<Q', pc, 24)[0]
	if not text and '.rela.dyn' in sections:
		_, roff, rsize = sections['.rela.dyn']
		relocated = {}
		for i in range(0, rsize - 23, 24):
			r_offset, _, addend = struct.unpack_from('<QQq', data, roff + i)
			relocated[r_offset] = addend
		pclntab = sections['.gopclntab'][0]
		for where, addend in relocated.items():
			if addend == pclntab and relocated.get(where + 160) and relocated.get(where + 160) == relocated.get(where + 176):
				text = relocated[where + 160]
				break
	if not text:   # a fixed-address program holds the pointers in the file: look for moduledata in the data sections
		needle = struct.pack('<Q', sections['.gopclntab'][0])
		for name in ('.go.module', '.noptrdata', '.data'):
			if name not in sections:
				continue
			_, doff, dsize = sections[name]
			block = data[doff:doff + dsize]
			at = block.find(needle)
			while at >= 0 and not text:
				if at + 184 <= len(block):
					minpc, etext = struct.unpack_from('<QQ', block, at + 160)[0], struct.unpack_from('<Q', block, at + 176)[0]
					if minpc and minpc == etext:
						text = minpc
				at = block.find(needle, at + 8)
	if not text:
		return None
	ftab = pcln_off
	out = []
	for i in range(nfunc):
		entry, funcoff = struct.unpack_from('<II', pc, ftab + i * 8)
		nameoff, = struct.unpack_from('<i', pc, pcln_off + funcoff + 4)
		end = pc.index(b'\0', funcname_off + nameoff)
		out.append((text + entry, pc[funcname_off + nameoff:end].decode('utf-8', 'replace')))
	out.sort()
	return out


def go_check(path, found, verbose):
	"""The verdict on a Go program: (problems, notes) where problems is a list of strings."""
	data = open(path, 'rb').read()
	sections = elf_sections(data)
	level = re.search(rb'build\tGOAMD64=(v[0-9])', data)
	problems, notes = [], []
	if not level:
		problems.append('the build info does not record GOAMD64, so the level the compiler targeted cannot be shown')
	elif level.group(1) != b'v1':
		problems.append('built for GOAMD64=%s: the compiler emits newer instructions in the program\'s own code' % level.group(1).decode())
	functions = go_functions(data, sections) if sections else None
	if functions is None:
		problems.append('the function names cannot be read from .gopclntab, so the newer instructions cannot be told from the program\'s own')
		return problems, notes
	addresses = [a for a, _ in functions]
	import bisect
	lines = {}
	for address, text in found:
		a = int(address, 16)
		i = bisect.bisect_right(addresses, a) - 1
		name = functions[i][1] if i >= 0 else '?'
		mnemonic = text.split()[0]
		if name.startswith(GO_DISPATCHED):
			notes.append((name, mnemonic, 'dispatched by CPUID'))
		elif GO_GUARDED.match(mnemonic) and address in GUARDED.get(path, ()):
			notes.append((name, mnemonic, 'guarded by a feature-byte test'))
		else:
			lines.setdefault(name, []).append(address + ' ' + text)
	for name, items in sorted(lines.items()):
		problems.append('%s holds %d newer instruction(s) outside the runtime-dispatched set and not behind a feature test, first %s' % (name, len(items), items[0]))
	return problems, notes



def above(path):
	"""The instructions above the baseline in one file: [(address, text)], or None when objdump cannot read it."""
	run = subprocess.run(['objdump', '-d', '--no-show-raw-insn', path], capture_output=True, text=True, errors='replace')
	if run.returncode != 0:
		sys.stderr.write(run.stderr)
		return None
	found = []
	GUARDED[path] = guarded = set()
	rows = []   # (address, mnemonic, operands) of every instruction, to see the shape of Go's guard around a newer one
	for line in run.stdout.splitlines():
		match = LINE.match(line)
		if not match:
			continue
		words = match.group(2).split()
		while len(words) > 1 and (words[0] in PREFIX or words[0].startswith('rex')):
			words.pop(0)
		rows.append((match.group(1), words[0], match.group(3)))
		if ABOVE.match(words[0]) or WIDE.search(match.group(3)):
			found.append((match.group(1), ' '.join(words) + ' ' + match.group(3).strip()))
	# Go's guard has one shape: `je FALLBACK; NEWER; jmp DONE; FALLBACK: ...`, the branch skipping the newer instruction to the
	# instruction right after the jmp (the flag was tested before, so the je may sit apart from its test)
	index = {address: i for i, (address, _, _) in enumerate(rows)}
	for address, _ in found:
		i = index[address]
		h = i - 1
		while h > 0 and i - h <= 4 and rows[h][1].startswith(('mov', 'lea', 'xor', 'pxor')):   # operand loads between the branch and the op
			h -= 1
		if h < 0 or rows[h][1] not in ('je', 'jne'):
			continue
		target = rows[h][2].split()[0]
		for j in (i + 1, i + 2):
			if j < len(rows) and rows[j][1] == 'jmp':
				k = j + 1
				while k < len(rows) and (rows[k][1].startswith('nop') or rows[k][1] in ('xchg', 'int3', 'data16')) and rows[k][0] != target:   # alignment padding
					k += 1
				if k < len(rows) and rows[k][0] == target:
					guarded.add(address)
	return found


def is_go(path):
	try:
		sections = elf_sections(open(path, 'rb').read())
	except OSError:
		return False
	return bool(sections) and '.go.buildinfo' in sections


def main(argv):
	verbose = '-v' in argv
	paths = [a for a in argv if a != '-v']
	if not paths:
		sys.stderr.write(__doc__)
		return 2
	status = 0
	for path in paths:
		found = above(path)
		if found is None:
			status = 2
			continue
		if is_go(path):
			problems, notes = go_check(path, found, verbose)
			if verbose:
				seen = {}
				for name, mnemonic, why in notes:
					seen.setdefault((name, why), set()).add(mnemonic)
				for (name, why), kinds in sorted(seen.items()):
					sys.stderr.write('  %s: %s (%s)\n' % (name, ' '.join(sorted(kinds)), why))
			if problems:
				status = max(status, 1)
				sys.stderr.write('%s: a Go program that needs more than the amd64 baseline:\n' % path)
				for p in problems[:20]:
					sys.stderr.write('  %s\n' % p)
			else:
				print('%s: Go program, GOAMD64=v1, %d newer instructions all in runtime-dispatched or guarded code' % (path, len(found)))
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
