# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Add reproducible Lean Code stages to a disposable, conventional dh source tree.

This is intentionally a checked preparation step, not an unrestricted rules
rewriter. A configure or clean hook the rules file already defines is kept and
the toolkit's commands join it as a prerequisite (ORDER 768b); any other custom
packaging hook still requires its own reviewed integration.
"""
import argparse
import datetime
import email.utils
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from . import source_tree


TARGETS = (
    "execute_before_dh_auto_configure",
    "execute_before_dh_auto_clean",
    "override_dh_builddeb",
)

HEADER = "\n\n# Distribution-only processing; authored source remains in the source archive.\n"
PROJECT = "\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.source_tree project $(CURDIR)\n"
RESTORE = ("\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.source_tree restore $(CURDIR)\n"
           "\trm -rf .sparky-lc\n")
BUILDDEB = ("override_dh_builddeb:\n"
            "\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.debhelper --provenance "
            "$(CURDIR)/debian/sparky-lean-toolkit/provenance.sh\n")
# ORDER 768b: a hook the rules file already defines (Debian's glib2.0: `execute_before_dh_auto_configure: cross-tools`) is
# kept as it is, and the toolkit's commands go into a target of its own that becomes a prerequisite of that hook.
# GNU make merges the prerequisites of all the rules of one target, in the order the rules appear, and runs them before
# the target's one recipe; the toolkit's rule is appended last, and `.WAIT` (GNU make 4.4) keeps it after the others under
# make -j. So the toolkit's commands run after the hook's own prerequisites and before its recipe:
# - the projection sees the tree as Debian's prerequisites leave it (they prepare inputs: glib's writes debian/cross-tools,
#   and debian/ is never projected) and runs before configure and compilation read the sources; a recipe of Debian's that
#   then edits a projected source makes the restore stop with that file's name ("Refusing to overwrite modified source");
# - the restore runs before Debian's clean recipe and dh_auto_clean, so they see the authored sources; it needs every
#   projected file as the projection left it, and stops with the file's name if a clean prerequisite of Debian's changed one.
# dh runs a plain hook target for every package and then never its -arch or -indep form (Debian::Debhelper::SequencerUtil,
# run_hook_target), so the toolkit's target joins the plain hook only when the rules file defines it; when it defines only
# the -arch or -indep form, the target joins both forms (the one it lacks is added with nothing else), so arch-only,
# indep-only and full builds run it. A full build then runs it twice; the second projection finds its record and returns,
# and the second restore finds no record.
KEPT = {
    "execute_before_dh_auto_configure": ("sparky-lean-source-project", PROJECT),
    "execute_before_dh_auto_clean": ("sparky-lean-source-restore", RESTORE),
}


def defined_targets(rules):
    """The toolkit's targets the rules file defines: {target: [(line, "" or "-arch" or "-indep", ":" or "::")]}."""
    found = {}
    pattern = re.compile("(" + "|".join(map(re.escape, TARGETS)) + r")(-arch|-indep)?\s*(::?)(?![:=])")
    for number, line in enumerate(rules.splitlines(), 1):
        m = pattern.match(line)
        if m:
            found.setdefault(m.group(1), []).append((number, m.group(2) or "", m.group(3)))
    return found


def kept_hook(target, rules_lines):
    name, commands = KEPT[target]
    variants = {variant for _, variant, _ in rules_lines}
    hooks = [target] if "" in variants else [target + "-arch", target + "-indep"]
    where = ", ".join(str(number) for number, _, _ in rules_lines)
    return (f"# debian/rules defines {target} itself (line {where}); that rule stays as it is, and {name}\n"
            "# runs as its prerequisite: after the rule's own prerequisites, before its recipe.\n"
            f".PHONY: {name}\n"
            + "".join(f"{hook}: .WAIT {name}\n" for hook in hooks)
            + f"{name}:\n" + commands)


def lean_rules(rules):
    """The text appended to the rules file, or ValueError naming the file and the line of a target it cannot keep."""
    found = defined_targets(rules)
    for number, variant, separator in found.get("override_dh_builddeb", ()):
        raise ValueError(f"debian/rules:{number}: Existing override_dh_builddeb: preserve and integrate its behavior explicitly")
    for target in KEPT:
        for number, variant, separator in found.get(target, ()):
            if separator == "::":
                raise ValueError(f"debian/rules:{number}: {target}{variant} is a double-colon rule, which a prerequisite "
                                 "rule cannot join; integrate it explicitly")
    sections = []
    for target, (name, commands) in KEPT.items():
        sections.append(kept_hook(target, found[target]) if target in found else f"{target}:\n{commands}")
    return HEADER + "\n".join(sections) + "\n" + BUILDDEB


def add_build_dependencies(control, dependencies):
    """Find the source stanza, preserving licence preambles and continuations."""
    paragraphs = re.split(r'(\n[ \t]*\n)', control)
    sources = [index for index, paragraph in enumerate(paragraphs)
               if re.search(r'^Source:', paragraph, re.M)]
    if len(sources) != 1:
        raise ValueError('Expected exactly one Source stanza in debian/control')
    index = sources[0]
    source = paragraphs[index]
    match = re.search(r'^Build-Depends:', source, re.M)
    addition = ', '.join(dependencies)
    if match:
        source = source[:match.end()] + ' ' + addition + ',' + source[match.end():]
    else:
        source += '\nBuild-Depends: ' + addition
    paragraphs[index] = source
    return ''.join(paragraphs)


def source_date_epoch():
    """The recipe's date for the changelog entry (ORDER 421, 421b): SOURCE_DATE_EPOCH, always UTC. There is no clock fallback:
    a source dated by the clock cannot be made again from its recipe, so the step stops and says what to set."""
    when = os.environ.get("SOURCE_DATE_EPOCH", "")
    if not when.isdigit():
        raise ValueError(
            "debian_prepare: " + ("SOURCE_DATE_EPOCH is not set" if not when else f"SOURCE_DATE_EPOCH={when!r} is not a number of seconds")
            + ": the changelog entry would be dated by the clock, and the source could not be made again byte for byte from its recipe. "
            "Export the recipe's date: python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR (the last commit touching the recipe), "
            "or run the build through sparky_provenance_init (sparky-os/repo/build-provenance.sh), which sets it.")
    return int(when)


def prepare(root, version, toolkit, build_dependencies=(), preserve_sources=(), generated_outputs=(), carried_plan=None):
    when = source_date_epoch()
    root, toolkit = Path(root).resolve(), Path(toolkit).resolve()
    rules_path = root / "debian/rules"
    rules = rules_path.read_text()
    # the dh call may follow one make variable (Debian's rustc: `$(SYSTEM_WORKAROUNDS) dh $@ --parallel`), nothing else
    if not re.search(r"^\s*(?:\$\([A-Z][A-Z0-9_]*\)[ \t]+)?dh\s+[\"']?\$(?:@|\{@\}|\(@\))(?=[\"'\s]|$)", rules, re.M):
        raise ValueError("Not a conventional dh rules file; integrate its builder explicitly")
    appended = lean_rules(rules)
    if "sparky-lean-toolkit" in rules:
        raise ValueError("Source is already integrated")
    old = subprocess.check_output(
        ["dpkg-parsechangelog", "-S", "Version"], cwd=root, text=True
    ).strip()
    if subprocess.run(["dpkg", "--compare-versions", version, "gt", old]).returncode:
        raise ValueError("The migration must advance the package version")
    destination = root / "debian/sparky-lean-toolkit"
    if destination.exists():
        raise ValueError("Refusing to replace an existing toolkit")
    # ORDER 435: the published source's plan (repo/plain-from-lc.py --save-plan FILE) comes first, then this call's own patterns
    carried = Path(carried_plan) if carried_plan else None
    carried_text = carried.read_text() if carried and carried.exists() else None
    carried_items = list(json.loads(carried_text).items()) if carried_text is not None else []
    own_items = list(preserve_sources)
    preserve_sources = carried_items + own_items
    preserve = {}
    for pattern, reason in preserve_sources:
        if (not pattern or pattern.startswith('/') or '..' in pattern.split('/')
                or '\\' in pattern or not reason.strip() or pattern in preserve):
            raise ValueError("Source preservation needs unique safe relative patterns and reasons")
        preserve[pattern] = reason
    preserve_path = root / 'debian/sparky-lean-preserve.json'
    if preserve and preserve_path.exists():
        raise ValueError("Preserve the existing source-consumer plan; do not replace it")
    if carried_text is not None and not own_items and json.dumps(preserve, indent=2) + '\n' != carried_text:
        source = subprocess.check_output(["dpkg-parsechangelog", "-S", "Source"], cwd=root, text=True).strip()
        raise ValueError(
            f"{source} {old}: the published source's debian/sparky-lean-preserve.json ({carried}) is not the form lean.debian_prepare "
            "writes, so the next source would not carry it byte for byte; no source is written without it. Rerun the package through "
            "repo/lc-successor.py, which keeps the published plan, or fix the plan in its recipe")
    generated = {}
    for pattern, form, reason in generated_outputs:
        if pattern in generated:
            raise ValueError(f"Generated output declared twice: {pattern}")
        generated[pattern] = {'form': form, 'reason': reason}
    source_tree.check_generated(generated)
    generated_path = root / source_tree.PAYLOAD_GENERATED_PLAN
    if generated and generated_path.exists():
        raise ValueError("Keep the existing generated-output plan; do not replace it")

    # Check all inputs before modifying the disposable source.
    for required in ("lean/source_tree.py", "lean/debhelper.py", "lean/smoke.tsv", "repo/provenance.sh",
                     "packages/dpkg-stereo/LICENSE"):
        if not (toolkit / required).is_file():
            raise ValueError(f"Missing toolkit input: {required}")
    control_path = root / "debian/control"
    control = control_path.read_text()
    dependencies = ["gcc", "node-acorn", "nodejs", "perl", "python3", "python3-yaml"]
    for dependency in build_dependencies:
        if not re.fullmatch(r"[a-z0-9][a-z0-9+.-]+(?: <!nocheck>)?", dependency):
            raise ValueError(f"Unsupported additional build dependency: {dependency!r}")
        dependencies.append(dependency)
    control = add_build_dependencies(control, dependencies)

    (destination / "lean").mkdir(parents=True)
    for path in (toolkit / "lean").glob("*.py"):
        shutil.copy2(path, destination / "lean" / path.name)
    shutil.copy2(toolkit / "lean/JvmLexer.java", destination / "lean/JvmLexer.java")
    shutil.copy2(toolkit / "lean/ZigTokens.zig", destination / "lean/ZigTokens.zig")
    shutil.copy2(toolkit / "lean/smoke.tsv", destination / "lean/smoke.tsv")
    shutil.copy2(toolkit / "repo/provenance.sh", destination / "provenance.sh")
    shutil.copy2(toolkit / "packages/dpkg-stereo/LICENSE", destination / "LICENSE")
    control_path.write_text(control)
    if preserve:
        preserve_path.write_text(json.dumps(preserve, indent=2) + '\n')
    if generated:
        generated_path.write_text(json.dumps(generated, indent=2) + '\n')
    # ORDER 421, 421b: the entry's date is the recipe's (SOURCE_DATE_EPOCH, always UTC), so the same recipe gives the same source.
    date = ["--date", email.utils.format_datetime(datetime.datetime.fromtimestamp(when, datetime.timezone.utc))]
    subprocess.run([
        "dch", *date, "--newversion", version, "--distribution", "UNRELEASED",
        "Apply verified native Lean Code before compilation and qualified lc1 "
        "payload assembly; retain exact authored source and HR companions.",
    ], cwd=root, check=True)
    rules_path.write_text(rules.rstrip() + appended)
    print(f"Prepared {root.name}: {old} -> {version}; native and payload stages retained in source")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("version")
    parser.add_argument("--toolkit", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--build-dependency", action="append", default=[],
                        help="Reviewed build prerequisite to retain in the source control file")
    parser.add_argument("--preserve-source", nargs=2, action="append", default=[],
                        metavar=("PATTERN", "REASON"),
                        help="Keep source read by an additional consumer unchanged; retained in source")
    parser.add_argument("--preserve-plan", type=Path, metavar="FILE",
                        help="The published source's source-consumer plan saved by repo/plain-from-lc.py --save-plan FILE; "
                             "its patterns are kept, then those of --preserve-source, and with no other pattern the written "
                             "plan must equal FILE byte for byte (a missing FILE is a source without a plan)")
    parser.add_argument("--generated-output", nargs=3, action="append", default=[],
                        metavar=("PATTERN", "FORM", "REASON"),
                        help="An installed file a build step generates from a source copy in an exact form "
                             "(empty, or sha256:HEX); every matching installed file must have it")
    args = parser.parse_args()
    try:
        prepare(args.root, args.version, args.toolkit, args.build_dependency, args.preserve_source,
                args.generated_output, args.preserve_plan)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + "\n")
