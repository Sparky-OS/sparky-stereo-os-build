#!/usr/bin/env python3
"""ORDER 400b: no container runs apt without the one helper, and no plain-HTTP apt source is written.

Why (CVE-2026-109518, DSA-6607-1): with Acquire::Retries, an attacker on the network path can swap a verified .deb
while apt retries a plain-HTTP download; the .deb then runs as root. Until apt 3.3.6 is in Debian testing every
container we start that runs apt begins with tools/https-only-apt.sh (Daniel, 2026-11-04: "change them to https",
"block http sources for now"). Remove this check's block when the helper goes; until then a new script that forgets
the helper fails here.

Three kinds of finding, each printed as FILE:LINE: reason.
  plain-http   a deb / deb-src / URIs: / bootstrap-mirror line that names http://
  dockerfile   a RUN that runs apt (or a bootstrap tool) without the two BuildKit mounts and the helper in front of it
  container-script  a script written for a container someone else starts (its usage line says docker run, or it checks
               /.dockerenv) that runs apt without the helper
  launcher     a script that starts a container (docker or podman run / create) and runs apt in it, directly or through
               a script of the same folder it names, without referring to tools/https-only-apt.sh

The Dockerfile form (one form, every Dockerfile; build with tools/https-only-build.sh, which names both contexts):
  RUN --mount=type=bind,from=https-only-apt,source=https-only-apt.sh,target=/run/https-only-apt.sh \\
      --mount=type=bind,from=host-ca,source=ca-certificates.crt,target=/run/host-ca.crt \\
      sh /run/https-only-apt.sh && apt-get ...

Use: python3 -I tests/https-only-apt/check.py [REPOSITORY]      Exit 0 when nothing is found, 1 otherwise (prints the count).
"""
import os
import re
import subprocess
import sys

# the repository to check: this one, or the one named by the first argument (red on an older checkout)
ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', '..'))
# upstream's own files (we run them only where a launcher names them, and those launchers are checked)
SKIP_DIRS = ('sparky-os/upstream/', 'kernel/series/', 'tests/https-only-apt/')
SKIP_NAMES = ('CHANGELOG', 'changelog', 'copyright', 'README', 'LICENSE')
SKIP_EXT = ('.md', '.patch', '.po', '.pot', '.svg', '.png', '.jpg', '.deb', '.dsc', '.json', '.html', '.xml', '.txt', '.debdiff')
# files that name http:// on purpose: the helper, the block file and the package that ships them
HTTP_OK = ('tools/https-only-apt.sh', 'sparky-os/packages/sparky-stereo-apt/')
# a launcher or Dockerfile that is allowed to run apt without the helper, with the reason (path -> why)
ALLOW = {
    'sparky-os/repo/publish-tree.sh': 'its only container is the AppStream generator, started with --network none: apt never runs in it',
    'sparky-os/release/check-host-upgrade.py': 'runs on the host, not in a container: it simulates the workstation upgrade with an isolated APT_CONFIG',
    'sparky-os/packages/sparky-stereo-ffmpeg-fdk/tests/test-engine.py': 'apt-get is a stub it writes (the file says: only APT and dispatch are fixtures)',
    'sparky-os/packages/sparky-stereo-service-defaults/test/run-tests.sh': 'the apt-get in it is text of a message the test matches: no apt runs',
    'sparky-os/packages/dpkg-stereo/test/no-fallbacks-test.sh': 'the apt-get in it is text of messages the test matches, and a stub apt-get it writes',
    'sparky-os/packages/sparky-stereo-hardware/tests/actions.sh': 'apt-get is a shell function stub and the apt lines are strings the test compares: no apt runs',
    'sparky-os/packages/sparky-stereo-hardware/tests/repair-lock.py': 'its apt.conf names one file: repository and an empty sourceparts: no network source exists',
    'sparky-os/packages/sparky-stereo-integration/tests/catalogue-proof.sh': 'it removes every apt source and writes one file: repository (/srv/repo): no network source exists',
}

# apt that reaches the network or the package lists: a verb of apt / apt-get / aptitude, a bootstrap tool, apt-file
APT_RE = re.compile(r'(?:^|[^\w./-])(?:apt-get|apt|aptitude|apt-file)\b[^\n|;&]*?\b(?:update|install|upgrade|dist-upgrade|full-upgrade|'
                    r'build-dep|source|download|satisfy|reinstall)\b|\b(?:mmdebstrap|debootstrap|apt_in)\b')
HTTP_RE = re.compile(r'(?:^|[^\w-])deb(?:-src)?\s+(?:\[[^\]]*\]\s*)?http://|URIs:\s*http://|'
                     r'\b(?:mmdebstrap|debootstrap)\b[^\n]*\bhttp://|--mirror[= ]\s*http://|\bMIRROR\w*=\S*http://')
START_RE = re.compile(r'\b(?:docker|podman)\b[^\n]*?\b(?:run|create)\b|[\'"](?:docker|podman)[\'"]\s*,\s*[\'"](?:run|create)[\'"]')


def tracked():
    out = subprocess.run(['git', '-C', ROOT, 'ls-files', '-z'], check=True, capture_output=True).stdout
    for rel in out.decode().split('\0'):
        if rel and not rel.startswith(SKIP_DIRS) and not rel.endswith(SKIP_EXT) and os.path.basename(rel) not in SKIP_NAMES:
            path = os.path.join(ROOT, rel)
            if os.path.isfile(path) and not os.path.islink(path):
                yield rel


def read(rel):
    try:
        with open(os.path.join(ROOT, rel), encoding='utf-8') as f:
            return f.read()
    except (UnicodeDecodeError, OSError):
        return None


def code_lines(text):
    """(number, line) of every line that is not a whole-line comment."""
    for n, line in enumerate(text.split('\n'), 1):
        if not line.lstrip().startswith('#'):
            yield n, line


def is_dockerfile(rel, text):
    return re.search(r'^FROM\s', text, re.M) is not None and re.search(r'(^|/)(Dockerfile|Containerfile)[^/]*$|\.Dockerfile$', rel) is not None


def dockerfile_runs(text):
    """(first line number, instruction text) of each RUN, with its backslash continuations joined."""
    lines = text.split('\n')
    i = 0
    while i < len(lines):
        if re.match(r'\s*RUN\b', lines[i]):
            start, parts = i + 1, [lines[i]]
            while parts[-1].rstrip().endswith('\\') and i + 1 < len(lines):
                i += 1
                parts.append(lines[i])
            yield start, '\n'.join(parts)
        i += 1


MOUNTS = ('from=https-only-apt', 'source=https-only-apt.sh', 'target=/run/https-only-apt.sh', 'from=host-ca', 'source=ca-certificates.crt',
          'target=/run/host-ca.crt')


def main():
    findings = []
    texts = {rel: read(rel) for rel in tracked()}
    texts = {rel: t for rel, t in texts.items() if t is not None}
    inner = {rel for rel, t in texts.items() if not is_dockerfile(rel, t) and any(APT_RE.search(l) for _, l in code_lines(t))}
    def named_by(other, rel, text):
        here = os.path.dirname(rel)
        return other != rel and (os.path.dirname(other) + '/').startswith(here + '/') and \
            re.search(r'(?<![\w.-])' + re.escape(os.path.basename(other)) + r'(?![\w-])', text) is not None

    # a script that a launcher with the helper already names runs under that launcher's helper
    covered = {other for rel, text in texts.items() if 'https-only-apt' in text and any(START_RE.search(l) for _, l in code_lines(text))
               for other in inner if named_by(other, rel, text)}
    for rel, text in sorted(texts.items()):
        if not rel.startswith(HTTP_OK):
            for n, line in code_lines(text):
                if HTTP_RE.search(line):
                    findings.append((rel, n, 'plain-http: ' + line.strip()[:110]))
        if rel in ALLOW:
            continue
        if is_dockerfile(rel, text):
            parent = os.path.dirname(os.path.dirname(rel))
            for n, run in dockerfile_runs(text):
                m = APT_RE.search(run)
                if not m:
                    # a RUN that names a script of the build context's folders that runs apt (dmo-setup.sh)
                    names = [x for x in inner if (os.path.dirname(x) + '/').startswith(parent + '/' if parent else '')
                             and re.search(r'(?<![\w.-])' + re.escape(os.path.basename(x)) + r'(?![\w-])', run)]
                    if not names:
                        continue
                    m = re.search(re.escape(os.path.basename(names[0])), run)
                helper = run.find('sh /run/https-only-apt.sh')
                if not (all(x in run for x in MOUNTS) and 0 <= helper < m.start()):
                    findings.append((rel, n, 'dockerfile: RUN runs apt without the https-only mounts and helper first'))
            continue
        starts = [n for n, l in code_lines(text) if START_RE.search(l)]
        if not starts:
            # a script written to run inside a container someone else starts: its own usage line or its /.dockerenv guard says so
            if rel in inner and rel not in covered and 'https-only-apt' not in text and re.search(r'docker run|podman run|/\.dockerenv|in-rootfs|in the audit image|Runs as root in|\bcontainer\b', '\n'.join(text.split('\n')[:25])):
                findings.append((rel, 1, 'container-script: written to run in a container and runs apt, without tools/https-only-apt.sh'))
            continue
        reason = None
        if rel in inner:
            reason = 'runs apt'
        else:
            for other in sorted(inner):
                if named_by(other, rel, text):
                    reason = 'starts ' + other + ', which runs apt'
                    break
        if reason and 'https-only-apt' not in text:
            findings.append((rel, starts[0], 'launcher: starts a container and ' + reason + ', without tools/https-only-apt.sh'))
    for rel, n, why in findings:
        print('%s:%d: %s' % (rel, n, why))
    kinds = {}
    for _, _, why in findings:
        kinds[why.split(':')[0]] = kinds.get(why.split(':')[0], 0) + 1
    print('https-only-apt check: %d finding(s) %s' % (len(findings), kinds))
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
