#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/30
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/30
"""kernel-keep.py --dry-run | --run | --queue RELEASE : the installed system keeps two kernels per flavour.

After a new kernel has installed successfully (its image, its boot image and its GRUB entry written), each kernel
flavour (the edition's base, v3 and rt; Debian's amd64, cloud-amd64 and rt-amd64) keeps the running kernel and the
newest, and when the newest is the running one, the one before it: never fewer than one, never the running one. The
other releases go: their packages only, purged (image, binary, modules, headers, the per-release base package, their
-dbg and Lean Code -lc-hr companions, and the per-version kbuild and headers-common packages no remaining package
needs), then their module folders that no package owns and that have no kernel in /boot, and their DKMS records;
then every kept kernel's boot image and GRUB's menu are written again. Never a general autoremove.

  --dry-run          prints the plan and changes nothing
  --run              the service (sparky-stereo-kernel-keep.service): waits until apt and dpkg are done, then carries
                     out the plan; only with a queued kernel install, never in a live session, a chroot or a container
  --queue RELEASE    the kernel hook (/etc/kernel/postinst.d/zz-sparky-stereo-kernel-keep): records the install

Environment, for tests: SPARKY_STEREO_KERNEL_KEEP_RUNNING=RELEASE stands for the running kernel;
SPARKY_STEREO_KERNEL_KEEP_TEST=1 lifts the guard against live sessions, chroots and containers.
"""
import fcntl
import functools
import glob
import os
import re
import shutil
import subprocess
import sys
import time

STATE = '/var/lib/sparky-stereo-boot'
QUEUE = os.path.join(STATE, 'kernel-keep.queue')
LOCKS = ('/var/lib/dpkg/lock-frontend', '/var/lib/dpkg/lock')
RELEASE = re.compile(r'^(\d+)\.(\d+)(?:\.(\d+))?(?:-rc\d+)?(.*)$')
# the packages of one release: linux-KIND-RELEASE, and their companions
KINDS = ('image', 'headers', 'modules', 'modules-extra', 'binary', 'binary-unsigned', 'base')
COMPANIONS = ('-lc-hr', '-dbgsym', '-dbg', '-unsigned')
# the packages a release's packages share with others of the same upstream version
SHARED = re.compile(r'^linux-(?:kbuild-\S+|headers-\S+-common)$')
TAG = 'sparky-stereo-kernel-keep'


def say(text):
    print('%s: %s' % (TAG, text), flush=True)


def guarded():
    """Why nothing may change here, or None: a live session, a chroot or a container (an image build installs one
    kernel only, and a live session's changes are lost anyway)."""
    if os.environ.get('SPARKY_STEREO_KERNEL_KEEP_TEST') == '1':
        return None
    try:
        if 'boot=live' in open('/proc/cmdline').read().split():
            return 'a live session'
    except OSError:
        pass
    if os.path.isdir('/run/live'):
        return 'a live session'
    for flag, what in (('--chroot', 'a chroot'), ('--container', 'a container')):
        try:
            if subprocess.run(['systemd-detect-virt', '--quiet', flag]).returncode == 0:
                return what
        except FileNotFoundError:
            pass
    if os.path.exists('/.dockerenv') or os.path.exists('/run/.containerenv'):
        return 'a container'
    if not os.path.isdir('/run/systemd/system'):
        return 'a system that systemd does not run'
    return None


def packages():
    """{package: (version, status, [depended-on names])} for every package dpkg knows (config-files included)."""
    out = subprocess.run(['dpkg-query', '-W', '-f', '${Package}\t${Version}\t${db:Status-Abbrev}\t${Depends}, ${Pre-Depends}\n'],
                         capture_output=True, text=True, check=True).stdout
    found = {}
    for line in out.splitlines():
        name, version, status, depends = (line.split('\t') + ['', '', ''])[:4]
        if status.startswith('un') or not name:
            continue
        found[name] = (version, status.strip(), [d.split()[0].split(':')[0] for d in re.split(r'[,|]', depends) if d.strip()])
    return found


def flavour(release):
    """The flavour of a release: 7.3.0-rc6-stereo3d12 and 7.3.1-stereo3d14 are -stereo3d, 7.3.0-stereo3d13-v3 is
    -stereo3d-v3, 7.3.0-rt-stereo3d13 is -rt-stereo3d; Debian's 7.2.12+deb14-amd64 is -amd64, -cloud-amd64, -rt-amd64."""
    m = RELEASE.match(release)
    rest = m.group(4) if m else release
    rest = re.sub(r'stereo3d\d+', 'stereo3d', rest)
    rest = re.sub(r'^\+deb\d+(?:u\d+)?', '', rest)
    return re.sub(r'^-\d+(?=-)', '', rest)


def compare(a, b):
    if a == b:
        return 0
    return -1 if subprocess.run(['dpkg', '--compare-versions', a, 'lt', b]).returncode == 0 else 1


def release_of(name):
    """The release a kernel package belongs to, or None."""
    for kind in sorted(KINDS, key=len, reverse=True):
        prefix = 'linux-%s-' % kind
        if name.startswith(prefix):
            rest = name[len(prefix):]
            for companion in COMPANIONS:
                if rest.endswith(companion):
                    rest = rest[:-len(companion)]
                    break
            if RELEASE.match(rest) and rest[0].isdigit():
                return rest
    return None


def complete(release):
    """Its image, boot image and GRUB entry are written (GRUB's only where GRUB's menu exists)."""
    if not (os.path.exists('/boot/vmlinuz-' + release) and os.path.exists('/boot/initrd.img-' + release)):
        return False
    cfg = '/boot/grub/grub.cfg'
    return not os.path.exists(cfg) or ('vmlinuz-%s ' % release) in open(cfg, errors='replace').read()


def plan(pkgs, running):
    """[(flavour, kept releases, removed releases, note)], the packages to purge, and the releases that go."""
    kernels = {}
    for name, (version, status, _) in pkgs.items():
        if name.startswith('linux-image-') and status == 'ii':
            r = release_of(name)
            if r and name == 'linux-image-' + r and os.path.exists('/boot/vmlinuz-' + r):
                kernels.setdefault(flavour(r), []).append((version, r))
    flavours, gone = [], []
    for f in sorted(kernels):
        ranked = [r for v, r in sorted(kernels[f], key=functools.cmp_to_key(lambda a, b: compare(a[0], b[0])), reverse=True)]
        newest = ranked[0]
        if not complete(newest):
            flavours.append((f, ranked, [], 'the newest, %s, has no boot image or GRUB entry yet: nothing removed' % newest))
            continue
        keep = [newest]
        if running in ranked and running != newest:
            keep.append(running)
        elif len(ranked) > 1:
            keep.append(ranked[1])
        removed = [r for r in ranked if r not in keep and r != running]
        flavours.append((f, keep, removed, ''))
        gone += removed
    purge = sorted(n for n in pkgs if release_of(n) in gone)
    staying = [n for n in pkgs if n not in purge and pkgs[n][1][1:2] == 'i']
    needed = {d for n in staying for d in pkgs[n][2]}
    shared = {d for n in purge for d in pkgs[n][2] if SHARED.match(d) and d in pkgs}
    shared |= {d + '-lc-hr' for d in shared if d + '-lc-hr' in pkgs}
    purge += sorted(d for d in shared if d not in needed and d not in purge)
    return flavours, purge, gone


def module_dirs():
    roots = ['/usr/lib/modules'] + ([] if os.path.islink('/lib') else ['/lib/modules'])
    return [os.path.join(r, n) for r in roots if os.path.isdir(r) for n in sorted(os.listdir(r))]


def owned(path):
    alias = path[4:] if path.startswith('/usr/lib/') else '/usr' + path
    return subprocess.run(['dpkg-query', '-S', path, alias], capture_output=True).returncode == 0


def leftovers(keep):
    """Module folders and DKMS records of releases that are neither kept nor in /boot, after the purge."""
    dirs = [d for d in module_dirs() if os.path.basename(d) not in keep
            and not os.path.exists('/boot/vmlinuz-' + os.path.basename(d)) and not owned(d)]
    dkms = []
    for path in sorted(glob.glob('/var/lib/dkms/*/*/*') + glob.glob('/var/lib/dkms/*/kernel-*')):
        name = os.path.basename(path)
        r = name[len('kernel-'):].rsplit('-', 1)[0] if name.startswith('kernel-') else name
        if RELEASE.match(r) and r[0].isdigit() and r not in keep and not os.path.exists('/boot/vmlinuz-' + r):
            dkms.append(path)
    return dirs, dkms


def show(flavours, purge, dirs, dkms, running):
    say('running kernel: %s' % running)
    for f, keep, removed, note in flavours:
        say('flavour %s: keeps %s%s' % (f, ' '.join(keep), '; removes ' + ' '.join(removed) if removed else '')
            + ('; ' + note if note else ''))
    for n in purge:
        say('purge %s' % n)
    for d in dirs:
        say('orphan module folder %s' % d)
    for d in dkms:
        say('DKMS record %s' % d)


def wait_for_dpkg():
    told = False
    while True:
        busy = False
        for path in LOCKS:
            try:
                fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o640)
            except OSError:
                continue
            try:
                fcntl.lockf(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                fcntl.lockf(fd, fcntl.LOCK_UN)
            except OSError:
                busy = True
            finally:
                os.close(fd)
        if not busy:
            return
        if not told:
            say('waiting until apt and dpkg are done')
            told = True
        time.sleep(2)


def run(command, **kw):
    say('runs ' + ' '.join(command))
    return subprocess.run(command, **kw)


def regenerate():
    """Every kept kernel's boot image, then GRUB's menu."""
    if shutil.which('update-initramfs'):
        run(['update-initramfs', '-u', '-k', 'all'])
    if shutil.which('update-grub') and os.path.exists('/boot/grub/grub.cfg'):
        run(['update-grub'])


def carry_out(running):
    pkgs = packages()
    flavours, purge, gone = plan(pkgs, running)
    keep = {r for _, k, _, _ in flavours for r in k} | {running}
    show(flavours, purge, [], [], running)
    if purge:
        env = dict(os.environ, DEBIAN_FRONTEND='noninteractive')
        apt = ['apt-get', '-o', 'APT::Get::AutomaticRemove=false', '-o', 'DPkg::Lock::Timeout=600']
        sim = subprocess.run(apt + ['-s', 'purge'] + purge, capture_output=True, text=True, env=env)
        would = {line.split()[1] for line in sim.stdout.splitlines() if line.startswith(('Purg ', 'Remv '))}
        if sim.returncode != 0 or would != set(purge):
            say('nothing removed: apt would remove %s, not exactly the plan' % (' '.join(sorted(would ^ set(purge))) or sim.stderr.strip()))
            return 1
        r = run(apt + ['-y', '-o', 'Dpkg::Options::=--force-confdef', '-o', 'Dpkg::Options::=--force-confold', 'purge'] + purge, env=env)
        if r.returncode != 0:
            say('apt-get purge failed (exit %d)' % r.returncode)
            return 1
    dirs, dkms = leftovers(keep)
    for d in dirs + dkms:
        if os.path.islink(d) or not os.path.isdir(d):
            os.remove(d)
        else:
            shutil.rmtree(d)
    for r in gone:
        say('removed %s: %s' % (r, ' '.join(n for n in purge if release_of(n) == r)))
    for d in dirs + dkms:
        say('removed %s' % d)
    if purge or dirs or dkms:
        regenerate()
    return 0


def main():
    args = sys.argv[1:]
    running = os.environ.get('SPARKY_STEREO_KERNEL_KEEP_RUNNING') or os.uname().release
    if args == ['--dry-run']:
        flavours, purge, gone = plan(packages(), running)
        keep = {r for _, k, _, _ in flavours for r in k} | {running}
        dirs, dkms = leftovers(keep | set(gone))
        show(flavours, purge, dirs, dkms, running)
        why = guarded()
        if why:
            say('dry run; in %s --run changes nothing' % why)
        return 0
    if len(args) == 2 and args[0] == '--queue':
        why = guarded()
        if why:
            return 0
        os.makedirs(STATE, exist_ok=True)
        with open(QUEUE, 'a') as f:
            f.write(args[1] + '\n')
        return 0
    if args == ['--run']:
        why = guarded()
        if why:
            say('nothing to do in %s' % why)
            return 0
        if not os.path.exists(QUEUE):
            say('no kernel install queued')
            return 0
        wait_for_dpkg()
        try:
            return carry_out(running)
        finally:
            if os.path.exists(QUEUE):
                os.remove(QUEUE)
    sys.exit(__doc__)


if __name__ == '__main__':
    sys.exit(main())
