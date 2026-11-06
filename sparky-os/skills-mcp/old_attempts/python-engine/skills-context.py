#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Select public maintainer instructions for humans and models without file tools."""
import argparse
import hashlib
import math
from pathlib import Path
import re
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parent.parent
COMMON = ('AGENTS.md', 'skills/sparky-stereo/SKILL.md', 'skills/ai-partners/SKILL.md')
PUBLIC = {'AGENTS.md', 'README.md', 'ATTRIBUTIONS.md', 'CITATION.cff',
          'LICENSE', 'LICENSE-GPL-2.0', 'SOURCE', 'MANIFEST.sha256', 'SOURCE-MANIFEST.sha256', 'skills', 'docs', 'tools'}


def public_file(root, name):
    rel = Path(name)
    if rel.is_absolute() or '..' in rel.parts or not rel.parts or rel.parts[0] not in PUBLIC:
        raise ValueError(f'Not a public relative path: {name}')
    p = (root / rel).resolve()
    if not p.is_relative_to(root.resolve()) or not p.is_file():
        raise ValueError(f'Missing or escaping public file: {name}')
    return p


def skill_path(root, name):
    if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', name):
        raise ValueError(f'Invalid skill name: {name}')
    return public_file(root, f'skills/{name}/SKILL.md')


def headings(text):
    # Ignore examples inside fenced code blocks.
    result = []
    fence = None
    for i, line in enumerate(text.splitlines(keepends=True)):
        stripped = line.lstrip()
        if stripped.startswith(('```', '~~~')):
            marker = stripped[:3]
            if fence == marker:
                fence = None
            elif fence is None:
                fence = marker
            continue
        if fence is None:
            m = re.match(r'^(#{1,6})\s+(.+?)\s*#*\s*$', line.rstrip('\n'))
            if m:
                result.append((i, len(m[1]), m[2]))
    return result


def selected_section(text, title):
    hs = headings(text)
    found = [h for h in hs if h[2] == title]
    if len(found) != 1:
        raise ValueError(f'Heading must match exactly once: {title!r}; use --list-sections')
    start, level, _ = found[0]
    lines = text.splitlines(keepends=True)
    end = next((i for i, depth, _ in hs if i > start and depth <= level), len(lines))
    # Preserve the skill identity/description, and label the excerpt explicitly.
    preamble = text.split('\n---\n', 1)[0] + '\n---\n' if text.startswith('---\n') else ''
    return preamble + '\n[Selected section; other sections are not included.]\n\n' + ''.join(lines[start:end])


def identity(root):
    source = root / 'SOURCE'
    if source.is_file():
        return public_file(root, 'SOURCE').read_text().strip()
    if (root / '.git').exists():
        head = subprocess.run(['git', '-C', str(root), 'rev-parse', 'HEAD'], capture_output=True, text=True, check=True).stdout.strip()
        dirty = subprocess.run(['git', '-C', str(root), 'status', '--porcelain'], capture_output=True, text=True, check=True).stdout
        return f'git {head}; working-tree changes: {bool(dirty)}'
    return 'Unversioned reference tree; use the file hashes below.'


def render(root, names, sections, references, limit):
    selections = [(n, None) for n in COMMON]
    for name in names:
        selections.append((str(skill_path(root, name).relative_to(root.resolve())), None))
    for value in sections:
        name, sep, title = value.partition(':')
        if not sep or not title:
            raise ValueError('--section needs skill-name:Exact heading')
        selections.append((str(skill_path(root, name).relative_to(root.resolve())), title))
    selections += [(name, None) for name in references]
    selections = list(dict.fromkeys(selections))
    parts = ['# Sparky Stereo OS selected maintainer context\n\n' + identity(root) + '\n\n'
             'Read instructions in the scope of the user’s task. Commands are not executed by this bundle.\n'
             'Relative links are relative to each source file; open additional references only when needed.\n']
    for name, title in selections:
        raw = public_file(root, name).read_bytes()
        text = raw.decode('utf-8')
        if title:
            text = selected_section(text, title)
        suffix = f' — section: {title}' if title else ''
        parts.append(f'\n---\nSource: {name}{suffix}\nFull-file SHA256: {hashlib.sha256(raw).hexdigest()}\n\n{text.rstrip()}\n')
    result = ''.join(parts)
    if len(result) > limit:
        raise ValueError(f'Context has {len(result)} characters; limit is {limit}. Select fewer skills/sections or explicitly increase --max-chars. Nothing was truncated.')
    return result


STOPWORDS = frozenset('''a about after all also an and any are as at be been before both but by can could did do does each
every for from had has have how i if in into is it its just may me might more most must my no not of on one only or other
our out over same should so some such than that the their them then there these they this those three to two under up us
very was we were what when where which who why will with without would you your'''.split())


def stem(word):
    # A few English endings, enough for "pins", "pinned" and "pin" to meet; deterministic, no dictionary.
    if len(word) > 4 and word.endswith('ies'):
        word = word[:-3] + 'y'
    elif len(word) > 3 and word.endswith('s') and not word.endswith('ss'):
        word = word[:-1]
    for suffix in ('ing', 'ed'):
        if len(word) > len(suffix) + 2 and word.endswith(suffix):
            word = word[:-len(suffix)]
            if len(word) > 2 and word[-1] == word[-2] and word[-1] not in 'lsz':
                word = word[:-1]
            break
    if len(word) > 4 and word.endswith('e'):
        word = word[:-1]
    return word


def terms(text):
    return {stem(w) for w in re.findall(r'[a-z0-9]+', text.lower()) if w not in STOPWORDS}


def description(text):
    if not text.startswith('---\n') or '\n---\n' not in text[4:]:
        return ''
    front = text[4:].split('\n---\n', 1)[0]
    try:
        import yaml
        data = yaml.safe_load(front)
        return data.get('description', '') if isinstance(data, dict) else ''
    except ImportError:
        m = re.search(r'^description:[ \t]*(?:[>|][-+]?[ \t]*\n)?((?:.*\S.*\n?)(?:[ \t]+.*\n?)*)', front + '\n', re.M)
        return ' '.join(m[1].split()) if m else ''


def task_rows(root):
    # The "Your task | Read next" table of skills/README.md: each row's task text routes to the skills it links.
    rows = {}
    readme = root / 'skills/README.md'
    if readme.is_file():
        for line in public_file(root, 'skills/README.md').read_text().splitlines():
            cells = [c.strip() for c in line.strip().strip('|').split('|')]
            if len(cells) < 2 or set(cells[0]) <= set('-: '):
                continue
            for name in re.findall(r'\(([a-z0-9]+(?:-[a-z0-9]+)*)/SKILL\.md\)', cells[1]):
                rows.setdefault(name, []).append(cells[0])
    return rows


FIELDS = (('name', 3.0), ('readme', 2.0), ('description', 1.0))


def find(root, query, limit):
    wanted = terms(query)
    if not wanted:
        raise ValueError('Describe the task or symptom in a few words')
    rows = task_rows(root)
    skills = []
    for path in sorted((root / 'skills').glob('*/SKILL.md')):
        name = path.parent.name
        text = skill_path(root, name).read_text()
        desc = description(text)
        skills.append((name, desc, {'name': terms(name.replace('-', ' ')),
                                    'readme': terms(' '.join(rows.get(name, []))),
                                    'description': terms(desc)}))
    count = len(skills)
    frequency = {t: sum(1 for _, _, f in skills if any(t in f[k] for k, _ in FIELDS)) for t in wanted}
    weight = {t: math.log(1 + (count - n + 0.5) / (n + 0.5)) for t, n in frequency.items()}
    scored = []
    for name, desc, fields in skills:
        score = sum(weight[t] * w for t in wanted for k, w in FIELDS if t in fields[k])
        if score > 0:
            scored.append((-round(score, 6), name, desc))
    return [(name, -score, desc) for score, name, desc in sorted(scored)[:limit]]


def bundle(root, destination):
    dest = Path(destination).resolve()
    if dest.is_relative_to(root.resolve()):
        raise ValueError('Place the bundle outside the reference tree')
    files = []
    for top in sorted(PUBLIC):
        p = root / top
        candidates = sorted(p.rglob('*')) if p.is_dir() else [p]
        for candidate in candidates:
            if not candidate.is_file() or '__pycache__' in candidate.parts or candidate.suffix == '.pyc':
                continue
            name = candidate.relative_to(root).as_posix()
            resolved = public_file(root, name)
            files.append((name, resolved))
    # Validate all paths before creating anything, and never overwrite a user's archive.
    with zipfile.ZipFile(dest, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
        for name, p in files:
            archive.write(p, name)
    return len(files)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('skills', nargs='*', help='Selected full skill names; common guidance is always included')
    parser.add_argument('--section', action='append', default=[], metavar='SKILL:HEADING')
    parser.add_argument('--reference', action='append', default=[], metavar='RELATIVE_PATH')
    parser.add_argument('--max-chars', type=int, default=48000, help='Character budget, not token count (default 48000)')
    parser.add_argument('--output', type=Path, help='New text file; default stdout; existing files are not overwritten')
    parser.add_argument('--list', action='store_true', help='List skill names')
    parser.add_argument('--list-sections', metavar='SKILL', help='List exact headings for section selection')
    parser.add_argument('--bundle', type=Path, help='New ZIP of the complete public reference tree, for ordinary extraction')
    parser.add_argument('--find', metavar='TEXT', help='Rank the skills for a task or symptom by name, description and the '
                        'skills index task table, offline and deterministic; prints each path and the context command to run next')
    parser.add_argument('--limit', type=int, default=3, help='How many skills --find prints (default 3)')
    parser.add_argument('--context-command', default=f'python3 {ROOT / "tools/skills-context.py"}', help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        if args.max_chars <= 0:
            raise ValueError('--max-chars must be positive')
        if args.find is not None:
            if args.skills or args.section or args.reference or args.output or args.list or args.list_sections or args.bundle:
                raise ValueError('--find is a separate operation')
            if args.limit <= 0:
                raise ValueError('--limit must be positive')
            found = find(ROOT, args.find, args.limit)
            if not found:
                print(f'No skill matches those words. Read the task table in {ROOT / "skills/README.md"}.')
                sys.exit(1)
            for i, (name, score, desc) in enumerate(found, 1):
                print(f'{i}. {name} (score {score:.2f})\n   {" ".join(desc.split())}\n'
                      f'   {ROOT / "skills" / name / "SKILL.md"}\n   Next: {args.context_command} {name}')
        elif args.bundle:
            if args.skills or args.section or args.reference or args.output or args.list or args.list_sections:
                raise ValueError('--bundle is a separate operation')
            print(f'Bundled {bundle(ROOT, args.bundle)} public files into {args.bundle}')
        elif args.list:
            print('\n'.join(p.parent.name for p in sorted((ROOT / 'skills').glob('*/SKILL.md'))))
        elif args.list_sections:
            print('\n'.join(title for _, _, title in headings(skill_path(ROOT, args.list_sections).read_text())))
        else:
            result = render(ROOT, args.skills, args.section, args.reference, args.max_chars)
            if args.output:
                with args.output.open('x', encoding='utf-8') as f:
                    f.write(result)
            else:
                sys.stdout.write(result)
    except (ValueError, OSError, UnicodeError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        parser.exit(2, f'{error}\n')


if __name__ == '__main__':
    main()
