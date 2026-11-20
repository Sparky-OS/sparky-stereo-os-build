#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check tracked shell/Python Docker run/create arguments without starting containers.

A core limit of exactly 1 suppresses the kernel's piped core helper; zero does not.
Shell continuations and locally declared argument arrays are followed. Python argv
lists are read with ast. Unresolved launch forms are reported, never executed.
Usage: check-container-core.py [BUILD_ROOT] [--revision COMMIT]
"""
import argparse
import ast
from pathlib import Path
import re
import shlex
import subprocess

SHELL_START = re.compile(r'\bdocker\s+(?:run|create)\b')
CORE = re.compile(r'--ulimit(?:=|\s+)[\x27\"]?core=([^\s\x27\";)]+)')
ARRAY_REF = re.compile(r'\$\{(\w+)\[@\]\}')
ARRAY = re.compile(r'^\s*(\w+)=\((.*?)(?:\)\s*(?:\n|$))', re.M | re.S)
# These are source-inspection statements or fixture text, not container launches.
TEXT_PREFIX = re.compile(r'^\s*(?:\w+=\$\()?\s*(?:grep|rg|sed|echo|printf)\b')


def logical_lines(text):
    parts, first = [], 1
    for number, line in enumerate(text.splitlines(), 1):
        if not parts:
            first = number
        parts.append(line.rstrip()[:-1] if line.rstrip().endswith('\\') else line)
        if line.rstrip().endswith('\\'):
            continue
        yield first, ' '.join(parts)
        parts = []
    if parts:
        yield first, ' '.join(parts)


# Docker switches without a following argument; other long/short options take a value.
SWITCHES = {'--rm', '-d', '--detach', '--init', '-i', '--interactive', '-t', '--tty',
            '--privileged', '--read-only', '--oom-kill-disable', '-P', '--publish-all'}


def option_prefix(words):
    """Only flags before the image count; flags inside a container's command do not."""
    result, i = [], 0
    while i < len(words):
        word = words[i]
        if ARRAY_REF.fullmatch(word):
            i += 1
            continue
        if word.startswith('${') and ':+' in word:
            while i < len(words) and '}' not in words[i]:
                i += 1
            i += 1
            continue
        if not word.startswith('-'):
            break
        result.append(word)
        if word not in SWITCHES and '=' not in word:
            i += 1
            if i < len(words):
                result.append(words[i])
        i += 1
    return ' '.join(result)


def shell_launches(text):
    arrays = {name: body for name, body in ARRAY.findall(text.replace('\\\n', ' '))}
    for number, line in logical_lines(text):
        if line.lstrip().startswith('#') or TEXT_PREFIX.match(line):
            continue
        starts = list(SHELL_START.finditer(line))
        for i, match in enumerate(starts):
            end = starts[i + 1].start() if i + 1 < len(starts) else len(line)
            command = line[match.end():end]
            # A quoted -c payload is not part of Docker's option list.
            # Find only complete shell words so quoted spaces stay in one word.
            try:
                words = shlex.split(command, comments=True)
            except ValueError:
                # Multiline shell payload starts here; Docker options precede it.
                command = re.split(r'\s+(?:sh|bash)\s+[^\n]*?-c\s+[\x27\"]', command, maxsplit=1)[0]
                try:
                    words = shlex.split(command, comments=True)
                except ValueError:
                    words = command.split()
            expanded = []
            for word in words:
                ref = ARRAY_REF.fullmatch(word)
                if ref and ref[1] in arrays and CORE.search(arrays[ref[1]]):
                    expanded.extend(shlex.split(arrays[ref[1]]))
                else:
                    expanded.append(word)
            yield number, option_prefix(expanded)


def python_launches(text):
    tree = ast.parse(text)
    for node in ast.walk(tree):
        if not isinstance(node, (ast.List, ast.Tuple)) or len(node.elts) < 2:
            continue
        first, second = node.elts[:2]
        docker = isinstance(first, ast.Constant) and first.value == 'docker'
        docker |= isinstance(first, ast.Attribute) and first.attr == 'docker'
        if not docker or not isinstance(second, ast.Constant) or second.value not in ('run', 'create'):
            continue
        words = []
        for item in node.elts[2:]:
            if isinstance(item, ast.Constant):
                words.append(str(item.value))
            elif isinstance(item, ast.IfExp) and all(isinstance(x, ast.Constant) and x.value in SWITCHES
                                                   for x in (item.body, item.orelse)):
                words.append(item.body.value)
            else:
                words.append('$dynamic')
        yield node.lineno, option_prefix(words)


def findings(rel, text):
    if rel.endswith('.py') or (text.startswith('#!') and 'python' in text.splitlines()[0]):
        launches = python_launches(text)
    elif rel.endswith('.sh') or re.match(r'#![^\n]*\b(?:ba|da|z|k)?sh\b', text):
        launches = shell_launches(text)
    else:
        return [], 0
    problems, count = [], 0
    for line, args in launches:
        count += 1
        values = CORE.findall(args)
        if values != ['1']:
            reason = f'core limit must be exactly 1 (found {values})' if values else 'container lacks --ulimit core=1'
            problems.append(f'{rel}:{line}: {reason}')
    return problems, count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', nargs='?', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--revision')
    args = parser.parse_args()
    root = args.root
    if args.revision:
        paths = subprocess.check_output(['git', '-C', str(root), 'ls-tree', '-r', '--name-only', args.revision], text=True).splitlines()
    else:
        paths = subprocess.check_output(['git', '-C', str(root), 'ls-files'], text=True).splitlines()
    problems, count = [], 0
    for rel in paths:
        path = root / rel
        if path.is_symlink() or not path.is_file():
            continue
        raw = (subprocess.check_output(['git', '-C', str(root), 'show', f'{args.revision}:{rel}'])
               if args.revision else path.read_bytes())
        if b'docker' not in raw or b'\0' in raw:
            continue
        try:
            text = raw.decode()
            found, n = findings(rel, text)
        except (UnicodeError, SyntaxError) as exc:
            problems.append(f'{rel}: cannot inspect: {exc}')
            continue
        problems.extend(found)
        count += n
    print('\n'.join(problems)) if problems else None
    print(f'container core check: {count} launchers, {len(problems)} findings')
    return int(bool(problems))


if __name__ == '__main__':
    raise SystemExit(main())
