#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/30
# Copyright 2026 under the GNU GPL3 License
# Tests of sparky-stereo-boot's kernel keeping and boot images (0.1.4), one case per fresh container, as root, with
# initramfs-tools, plymouth, plymouth-themes, grub-common, grub2-common and python3 installed:
#   kernel-keep-tests.py CASE BOOT.deb [OLD-BOOT.deb]
# Kernels are small packages made here with Debian's kernel maintainer scripts (the /etc/kernel hooks with
# DEB_MAINT_PARAMS), in the edition's names (linux-image, linux-headers and -lc-hr per release) and in Debian's split
# names (linux-image, linux-binary, linux-modules, linux-base and linux-headers per release, linux-kbuild and
# linux-headers-common per version). initramfs-tools writes their boot images; update-grub writes GRUB's menu, with a
# stub for GRUB's device probe, which finds no disk in a container. The running kernel comes from
# SPARKY_STEREO_KERNEL_KEEP_RUNNING; SPARKY_STEREO_KERNEL_KEEP_TEST=1 lifts the container guard, except in "guard".
import fcntl, glob, os, subprocess, sys, tempfile, time

CASE, NEW = sys.argv[1], sys.argv[2]
OLD = sys.argv[3] if len(sys.argv) > 3 else None
KEEP = '/usr/lib/sparky-stereo-boot/kernel-keep.py'
QUEUE = '/var/lib/sparky-stereo-boot/kernel-keep.queue'
W = tempfile.mkdtemp(prefix='kernel-keep-tests-')
E = {12: ('7.3.0-rc6-stereo3d12', '7.3.0~rc6-12+lc1'), 13: ('7.3.0-stereo3d13', '7.3.0-13+lc1'),
     14: ('7.3.1-stereo3d14', '7.3.1-14+lc1'), 15: ('7.3.2-stereo3d15', '7.3.2-15+lc1')}
D = {10: ('7.2.10+deb14-amd64', '7.2.10-1', '7.2.10+deb14'), 11: ('7.2.11+deb14-amd64', '7.2.11-1', '7.2.11+deb14'),
     12: ('7.2.12+deb14-amd64', '7.2.12-1', '7.2.12+deb14')}
DRT = ('7.2.10+deb14-rt-amd64', '7.2.10-1', '7.2.10+deb14')
results = []


def sh(cmd, check=True, **kw):
    r = subprocess.run(cmd, shell=isinstance(cmd, str), capture_output=True, text=True, **kw)
    if check and r.returncode:
        raise SystemExit('FAIL  %s: %s exited %d\n%s%s' % (CASE, cmd, r.returncode, r.stdout, r.stderr))
    return r


def check(ok, text):
    results.append(ok)
    print(('PASS  ' if ok else 'FAIL  ') + '%s: %s' % (CASE, text), flush=True)


KERNEL_SCRIPTS = {
    'postinst': '#!/bin/sh\nset -e\n[ "$1" = configure ] || exit 0\ndepmod -a {r} || true\nexport DEB_MAINT_PARAMS="$*"\n'
                'run-parts --report --exit-on-error --arg={r} --arg=/boot/vmlinuz-{r} /etc/kernel/postinst.d\n',
    'prerm': '#!/bin/sh\nset -e\nexport DEB_MAINT_PARAMS="$*"\n[ ! -d /etc/kernel/prerm.d ] || '
             'run-parts --report --exit-on-error --arg={r} --arg=/boot/vmlinuz-{r} /etc/kernel/prerm.d\n',
    'postrm': '#!/bin/sh\nset -e\nexport DEB_MAINT_PARAMS="$*"\n[ ! -d /etc/kernel/postrm.d ] || '
              'run-parts --report --arg={r} --arg=/boot/vmlinuz-{r} /etc/kernel/postrm.d\n'
              'if [ "$1" = remove ] || [ "$1" = purge ]; then rm -f /usr/lib/modules/{r}/modules.*; fi\n',
}


def deb(name, version, source, depends='', boot=None, modules=None, scripts=None, fail=False):
    d = os.path.join(W, 'b', name)
    os.makedirs(os.path.join(d, 'DEBIAN'))
    if boot:
        os.makedirs(os.path.join(d, 'boot'))
        open(os.path.join(d, 'boot', 'vmlinuz-' + boot), 'wb').write(b'\0' * 64)
        open(os.path.join(d, 'boot', 'config-' + boot), 'w').write('CONFIG_BLK_DEV_INITRD=y\nCONFIG_RD_ZSTD=y\nCONFIG_RD_GZIP=y\n')
        open(os.path.join(d, 'boot', 'System.map-' + boot), 'w').close()
    if modules:
        m = os.path.join(d, 'usr/lib/modules', modules)
        os.makedirs(os.path.join(m, 'kernel'))
        for f in ('modules.order', 'modules.builtin', 'modules.builtin.modinfo'):
            open(os.path.join(m, f), 'w').close()
    doc = os.path.join(d, 'usr/share/doc', name)
    os.makedirs(doc, exist_ok=True)
    open(os.path.join(doc, 'README'), 'w').write(name + '\n')
    control = 'Package: %s\nVersion: %s\nArchitecture: amd64\nMaintainer: Test <test@example.invalid>\nSource: %s\n' % (name, version, source)
    if depends:
        control += 'Depends: %s\n' % depends
    open(os.path.join(d, 'DEBIAN/control'), 'w').write(control + 'Description: test package %s\n' % name)
    for s, text in (scripts or {}).items():
        p = os.path.join(d, 'DEBIAN', s)
        open(p, 'w').write(('#!/bin/sh\nexit 1\n' if fail and s == 'postinst' else text.replace('{r}', scripts['_r'])) if s != '_r' else '')
        os.chmod(p, 0o755)
    if scripts:
        os.remove(os.path.join(d, 'DEBIAN/_r'))
    out = os.path.join(W, name + '.deb')
    sh(['dpkg-deb', '--root-owner-group', '-b', d, out])
    return out


def edition(n, fail=False):
    r, v = E[n]
    image = deb('linux-image-' + r, v, 'linux-stereo-base', 'kmod, initramfs-tools', boot=r, modules=r,
                scripts=dict(KERNEL_SCRIPTS, _r=r), fail=fail)
    return [image, deb('linux-headers-' + r, v, 'linux-stereo-base'), deb('linux-headers-%s-lc-hr' % r, v, 'linux-stereo-base')]


def split(r, v, ver, with_shared=True):
    """A Debian kernel in forky's split packages, with its per-version kbuild and headers-common."""
    debs = [deb('linux-base-' + r, v, 'linux'), deb('linux-binary-' + r, v, 'linux-signed-amd64', 'linux-base-%s (= %s)' % (r, v), boot=r),
            deb('linux-modules-' + r, v, 'linux', modules=r),
            deb('linux-image-' + r, v, 'linux-signed-amd64', 'linux-binary-%s, linux-modules-%s, linux-base-%s, initramfs-tools' % (r, r, r),
                scripts=dict(KERNEL_SCRIPTS, _r=r)),
            deb('linux-headers-' + r, v, 'linux', 'linux-headers-%s-common, linux-kbuild-%s' % (ver, ver))]
    if with_shared:
        debs = [deb('linux-kbuild-' + ver, v, 'linux'), deb('linux-headers-%s-common' % ver, v, 'linux')] + debs
    return debs


def install(debs, check_rc=True):
    r = sh(['dpkg', '-i'] + debs, check=check_rc)
    # Debian's /etc/kernel/postinst.d/zz-update-grub exits in a container; on a machine it writes GRUB's menu after a
    # kernel's install, after the edition's hook, so the bench does it here
    if r.returncode == 0 and any(os.path.basename(d).startswith('linux-image-') for d in debs):
        sh('update-grub')
    return r


def installed():
    out = sh("dpkg-query -W -f '${Package} ${db:Status-Abbrev}\\n'").stdout
    return {l.split()[0]: l.split()[1] for l in out.splitlines() if len(l.split()) > 1 and not l.split()[1].startswith('un')}


def keep_run(**env):
    t = time.time()
    r = sh([KEEP, '--run'], check=False, env=dict(os.environ, **env))
    print('   ' + r.stdout.strip().replace('\n', '\n   '), flush=True)
    return r, time.time() - t


def grub_kernels():
    text = open('/boot/grub/grub.cfg').read()
    return sorted({w[len('/boot/vmlinuz-'):] for w in text.split() if w.startswith('/boot/vmlinuz-')})


def has_image(r):
    return installed().get('linux-image-' + r, '').startswith('ii')


def setup(boot_deb):
    # grub-mkconfig calls ${sbindir}/grub-probe by its path: the bench's own programs move aside (a throwaway container)
    for real in ('/usr/sbin/grub-probe', '/usr/bin/grub-mkrelpath'):
        sh(['dpkg-divert', '--local', '--rename', '--add', real])
    open('/usr/sbin/grub-probe', 'w').write(
        '#!/bin/sh\ncase "$*" in\n*--target=device*) echo /dev/vda2 ;;\n*--target=fs_uuid*) echo 0b1c2d3e-0000-4000-8000-000000000001 ;;\n'
        '*--target=partmap*) echo gpt ;;\n*--target=abstraction*) ;;\n*--target=drive*) echo "(hd0,gpt2)" ;;\n'
        '*--target=compatibility_hint*) echo hd0,gpt2 ;;\n*--target=hints_string*) echo --hint=hd0,gpt2 ;;\n*) echo ext2 ;;\nesac\n')
    open('/usr/bin/grub-mkrelpath', 'w').write('#!/bin/sh\necho "$1"\n')
    for f in ('/usr/sbin/grub-probe', '/usr/bin/grub-mkrelpath'):
        os.chmod(f, 0o755)
    os.makedirs('/etc/default', exist_ok=True)
    open('/etc/default/grub', 'w').write('GRUB_DEFAULT=0\nGRUB_TIMEOUT=5\nGRUB_DISTRIBUTOR=Test\nGRUB_CMDLINE_LINUX_DEFAULT=quiet\n'
                                         'GRUB_CMDLINE_LINUX=""\nGRUB_DISABLE_OS_PROBER=true\n')
    os.makedirs('/boot/grub', exist_ok=True)
    open('/boot/grub/grub.cfg', 'w').close()
    install([boot_deb])


def main():
    guard = CASE == 'guard'
    if not guard:
        os.environ['SPARKY_STEREO_KERNEL_KEEP_TEST'] = '1'
    running = {'edition': E[13][0], 'newest-running': E[14][0], 'running-older': E[12][0], 'second-flavour': E[13][0],
               'debian-split': E[13][0], 'shared-kept': E[13][0], 'one-kernel': E[14][0], 'failed-install': E[14][0],
               'lock-wait': E[13][0], 'guard': E[13][0], 'edition-0.1.3': E[13][0], 'plymouth': E[14][0],
               'plymouth-0.1.3': E[14][0], 'upgrade': E[14][0]}[CASE]
    os.environ['SPARKY_STEREO_KERNEL_KEEP_RUNNING'] = running
    setup(OLD if CASE in ('edition-0.1.3', 'plymouth-0.1.3', 'upgrade') else NEW)
    has_keep = os.path.exists(KEEP)

    def kernels_in_turn(ns, after=None):
        for n in ns:
            install(edition(n))
            if has_keep:
                keep_run()
            if after:
                after(n)

    if CASE in ('edition', 'edition-0.1.3', 'newest-running', 'running-older'):
        cuda = None
        if CASE == 'edition':
            # what apt calls automatically installed, not a kernel: a general autoremove would take it
            install([deb('cuda-toolkit-like', '13.0-1', 'cuda-toolkit-like')])
            sh('apt-mark auto cuda-toolkit-like')
            cuda = 'Remv cuda-toolkit-like' in sh('apt-get -s autoremove').stdout
            check(cuda, 'control: apt-get -s autoremove would remove the automatically installed cuda-toolkit-like')
        before = {}
        if CASE == 'edition':
            for n in (12, 13):
                install(edition(n))
                keep_run()
            for r in (E[13][0],):
                before[r] = os.stat('/boot/initrd.img-' + r).st_mtime
            time.sleep(1.1)
            install(edition(14))
            before[E[14][0]] = os.stat('/boot/initrd.img-' + E[14][0]).st_mtime
            # an orphan module folder, and DKMS records for the kernel that goes and for a kept one
            os.makedirs('/usr/lib/modules/7.1.9-stereo3d9/updates')
            for n in (12, 14):
                os.makedirs('/var/lib/dkms/fakemod/1.0/%s/x86_64/module' % E[n][0])
                os.symlink('1.0/%s' % E[n][0], '/var/lib/dkms/fakemod/kernel-%s-x86_64' % E[n][0])
            time.sleep(1.1)
            r, _ = keep_run()
        else:
            kernels_in_turn((12, 13, 14))
        want = {'edition': (13, 14), 'edition-0.1.3': (12, 13, 14), 'newest-running': (13, 14), 'running-older': (12, 14)}[CASE]
        have = tuple(n for n in (12, 13, 14) if has_image(E[n][0]))
        check(have == want, 'kernels kept %s, expected %s (running %s)' % (have, want, running))
        check(has_image(running), 'the running kernel %s stays' % running)
        pk = installed()
        gone = [n for n in (12, 13, 14) if n not in want]
        for n in gone:
            left = [p for p in pk if E[n][0] in p]
            check(not left, 'no package of %s is left (%s)' % (E[n][0], ' '.join(left) or 'none'))
            check(not os.path.exists('/usr/lib/modules/' + E[n][0]), 'its module folder is gone')
        if has_keep:
            check(grub_kernels() == sorted(E[n][0] for n in want), "GRUB's menu lists exactly %s (%s)" % (want, ' '.join(grub_kernels())))
            check(not os.path.exists(QUEUE), 'the queue is cleared')
        if CASE == 'edition':
            check('linux-headers-%s-lc-hr' % E[12][0] not in pk, 'the -lc-hr companion went with its kernel')
            check(pk.get('cuda-toolkit-like', '').startswith('ii'), 'cuda-toolkit-like, automatically installed, stays')
            check(not os.path.exists('/usr/lib/modules/7.1.9-stereo3d9'), 'the orphan module folder 7.1.9-stereo3d9 is gone')
            check(not os.path.exists('/var/lib/dkms/fakemod/1.0/' + E[12][0]) and not os.path.lexists('/var/lib/dkms/fakemod/kernel-%s-x86_64' % E[12][0]),
                  "the removed kernel's DKMS record is gone")
            check(os.path.isdir('/var/lib/dkms/fakemod/1.0/' + E[14][0]), "the kept kernel's DKMS record stays")
            for k in (E[13][0], E[14][0]):
                check(os.stat('/boot/initrd.img-' + k).st_mtime > before[k], 'the boot image of %s was written again after the purge' % k)
            check(('removed %s: linux-headers-%s linux-headers-%s-lc-hr linux-image-%s' % ((E[12][0],) * 4)) in r.stdout,
                  'one log line names the removed release and its packages')
    elif CASE in ('second-flavour', 'debian-split', 'shared-kept'):
        if CASE == 'second-flavour':
            kernels_in_turn((12, 13, 14))
        for n in (10, 11, 12):
            install(split(*D[n]))
            if CASE == 'shared-kept' and n == 10:
                install(split(*DRT, with_shared=False))
            keep_run()
        pk = installed()
        if CASE == 'second-flavour':
            check(tuple(n for n in (12, 13, 14) if has_image(E[n][0])) == (13, 14), "the edition's flavour keeps 13 and 14")
        check(tuple(n for n in (10, 11, 12) if has_image(D[n][0])) == (11, 12), "Debian's amd64 flavour keeps its own two, 11 and 12")
        left = [p for p in pk if D[10][0] in p]
        check(not left, 'no split package of %s is left (%s)' % (D[10][0], ' '.join(left) or 'none'))
        shared = [p for p in ('linux-kbuild-7.2.10+deb14', 'linux-headers-7.2.10+deb14-common') if p in pk]
        if CASE == 'shared-kept':
            check(has_image(DRT[0]), 'the rt flavour keeps its only kernel')
            check(len(shared) == 2, 'kbuild and headers-common of 7.2.10 stay: the kept rt kernel needs them (%s)' % ' '.join(shared))
        else:
            check(not shared, 'kbuild and headers-common of 7.2.10 go: nothing else needs them (%s)' % (' '.join(shared) or 'none left'))
        check(all(p in pk for p in ('linux-kbuild-7.2.11+deb14', 'linux-kbuild-7.2.12+deb14')), 'the kept kernels keep their kbuild')
        expect = sorted([D[11][0], D[12][0]] + ([DRT[0]] if CASE == 'shared-kept' else []) + ([E[13][0], E[14][0]] if CASE == 'second-flavour' else []))
        check(grub_kernels() == expect, "GRUB's menu lists exactly the kept kernels (%s)" % ' '.join(grub_kernels()))
    elif CASE == 'one-kernel':
        kernels_in_turn((14,))
        check(has_image(E[14][0]) and len([p for p in installed() if p.startswith('linux-image-')]) == 1, 'the only kernel stays')
    elif CASE == 'failed-install':
        kernels_in_turn((13, 14))
        r = install(edition(15, fail=True), check_rc=False)
        check(r.returncode != 0 and installed().get('linux-image-' + E[15][0], '')[:2] in ('iF', 'iU'),
              'the kernel 15 install failed (%s)' % installed().get('linux-image-' + E[15][0]))
        check(not os.path.exists(QUEUE), 'its hook was not reached: nothing queued')
        r, _ = keep_run()
        check('no kernel install queued' in r.stdout, 'the service finds nothing queued')
        open(QUEUE, 'w').write(E[15][0] + '\n')
        r, _ = keep_run()
        check(has_image(E[13][0]) and has_image(E[14][0]), 'even with a stray queue, 13 and 14 stay: the half-installed 15 counts for nothing')
    elif CASE == 'lock-wait':
        kernels_in_turn((12, 13))
        install(edition(14))
        fd = os.open('/var/lib/dpkg/lock-frontend', os.O_RDWR | os.O_CREAT)
        holder = subprocess.Popen([sys.executable, '-c', 'import fcntl,os,time\nfd=os.open("/var/lib/dpkg/lock-frontend",os.O_RDWR)\n'
                                   'fcntl.lockf(fd,fcntl.LOCK_EX)\nopen("/tmp/held","w").close()\ntime.sleep(8)'])
        os.close(fd)
        while not os.path.exists('/tmp/held'):
            time.sleep(0.1)
        r, took = keep_run()
        holder.wait()
        check('waiting until apt and dpkg are done' in r.stdout and took >= 7, 'the service waited for the lock (%.1f s)' % took)
        check(not has_image(E[12][0]) and has_image(E[13][0]) and has_image(E[14][0]), 'then it ran: 12 removed, 13 and 14 kept')
    elif CASE == 'guard':
        for n in (12, 13, 14):
            install(edition(n))
        check(not os.path.exists(QUEUE), 'in a container the hook queues nothing')
        r, _ = keep_run()
        check('nothing to do in a container' in r.stdout, 'the service does nothing in a container')
        check(all(has_image(E[n][0]) for n in (12, 13, 14)), 'all three kernels stay')
        dry = sh([KEEP, '--dry-run']).stdout
        check('removes %s' % E[12][0] in dry and 'in a container --run changes nothing' in dry, 'the dry run shows the plan and the guard')
    elif CASE in ('plymouth', 'plymouth-0.1.3'):
        for n in (13, 14):
            install(edition(n))
        sh('plymouth-set-default-theme solar')
        sh('update-initramfs -u')
        themed = [n for n in (13, 14) if 'usr/share/plymouth/themes/solar/solar.plymouth' in sh(['lsinitramfs', '/boot/initrd.img-' + E[n][0]]).stdout]
        want = (14,) if CASE == 'plymouth-0.1.3' else (13, 14)
        check(tuple(themed) == want, 'after a theme change and update-initramfs -u, the boot images with it: %s (expected %s)' % (tuple(themed), want))
    elif CASE == 'upgrade':
        for n in (13, 14):
            install(edition(n))
        debian_md5 = sh('md5sum /etc/initramfs-tools/update-initramfs.conf').stdout.split()[0]
        pk = installed()
        mt = {n: os.stat('/boot/initrd.img-' + E[n][0]).st_mtime for n in (13, 14)}
        time.sleep(1.1)
        install([NEW])
        after = installed()
        check(set(after) == set(pk) and all(after[p] == pk[p] for p in pk), 'installing 0.1.4 over 0.1.3 removes and changes no other package')
        div = sh('dpkg-divert --list /etc/initramfs-tools/update-initramfs.conf').stdout.strip()
        check('update-initramfs.conf.debian by sparky-stereo-boot' in div, 'the diversion is in place (%s)' % div)
        check(os.readlink('/etc/initramfs-tools/update-initramfs.conf') == 'update-initramfs.conf.sparky-stereo'
              and 'update_initramfs=all' in open('/etc/initramfs-tools/update-initramfs.conf').read(), 'update-initramfs reads update_initramfs=all')
        check(sh('md5sum /etc/initramfs-tools/update-initramfs.conf.debian').stdout.split()[0] == debian_md5, "initramfs-tools' file kept as .debian")
        check(all(os.stat('/boot/initrd.img-' + E[n][0]).st_mtime > mt[n] for n in (13, 14)), "both kernels' boot images were written at the upgrade")
        check(not os.path.exists(QUEUE) and has_image(E[13][0]), 'nothing queued and nothing removed at install time')
        install(edition(15))
        check(os.path.exists(QUEUE), 'the next kernel install queues the work')
        keep_run()
        check(not has_image(E[13][0]) and has_image(E[14][0]) and has_image(E[15][0]), 'then 13 goes, 14 (running) and 15 stay')
        sh('dpkg -r sparky-stereo-boot')
        p = '/etc/initramfs-tools/update-initramfs.conf'
        check(not os.path.islink(p) and sh(['md5sum', p]).stdout.split()[0] == debian_md5 and not os.path.exists(p + '.debian')
              and not sh('dpkg-divert --list ' + p).stdout.strip(), "removal brings initramfs-tools' own file back, undiverted")
        sh('dpkg -P sparky-stereo-boot')
        check(not os.path.exists(p + '.sparky-stereo'), "purge removes the edition's file")
    print('== %s: %s' % (CASE, 'ALL PASS' if all(results) else '%d FAILED' % results.count(False)))
    sys.exit(0 if all(results) else 1)


if __name__ == '__main__':
    main()
