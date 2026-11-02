#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/01
# Copyright 2026 under the GNU GPL3 License
# Tests of sparky-stereo-boot's maintainer scripts and kernel hook when a boot step fails (0.1.5), one case per fresh
# container, as root, with grub-common, grub2-common, initramfs-tools and python3 installed:
#   package-failure-tests.py CASE BOOT.deb
# A failing update-grub, update-initramfs or grub-editenv is a stub put in place with dpkg-divert --local (a throwaway
# container; grub-editenv cannot write an environment block on a container's overlay file system at all, "failed to
# get canonical path of `overlay'"); the EFI system partition is a folder named in /etc/fstab. Nothing here touches
# a real boot.
import json, os, subprocess, sys

CASE, DEB = sys.argv[1], sys.argv[2]
PROBLEMS = '/var/lib/sparky-stereo-boot/problems'
results = []


def sh(cmd, check=True, env=None):
    r = subprocess.run(cmd, shell=isinstance(cmd, str), capture_output=True, text=True, env=env)
    if check and r.returncode:
        raise SystemExit('FAIL  %s: %s exited %d\n%s%s' % (CASE, cmd, r.returncode, r.stdout, r.stderr))
    return r


def check(ok, text):
    results.append(ok)
    print(('PASS  ' if ok else 'FAIL  ') + '%s: %s' % (CASE, text), flush=True)


def state():
    return sh("dpkg-query -W -f '${db:Status-Abbrev}' sparky-stereo-boot", check=False).stdout.strip()


def kept(step):
    try:
        return json.load(open(os.path.join(PROBLEMS, step + '.json')))
    except (OSError, ValueError):
        return None


def stub(path, body):
    """PATH becomes a script (the real program kept as PATH.distrib); BODY may call "$REAL"."""
    if not os.path.exists(path + '.distrib'):
        sh(['dpkg-divert', '--local', '--rename', '--add', path])
    open(path, 'w').write('#!/bin/sh\nREAL=%s.distrib\n%s\n' % (path, body))
    os.chmod(path, 0o755)


def grub_setup():
    """GRUB's menu exists, and grub-mkconfig's device probe answers as on a disk (a container has none)."""
    stub('/usr/sbin/grub-probe', 'case "$*" in\n*--target=device*) echo /dev/vda2 ;;\n*--target=fs_uuid*) echo 0b1c2d3e-0000-4000-8000-000000000001 ;;\n'
         '*--target=partmap*) echo gpt ;;\n*--target=abstraction*) ;;\n*--target=drive*) echo "(hd0,gpt2)" ;;\n'
         '*--target=compatibility_hint*) echo hd0,gpt2 ;;\n*--target=hints_string*) echo --hint=hd0,gpt2 ;;\n*) echo ext2 ;;\nesac')
    stub('/usr/bin/grub-mkrelpath', 'echo "$1"')
    open('/etc/default/grub', 'w').write('GRUB_DEFAULT=0\nGRUB_TIMEOUT=5\nGRUB_DISTRIBUTOR=Test\nGRUB_CMDLINE_LINUX_DEFAULT=quiet\n'
                                         'GRUB_CMDLINE_LINUX=""\nGRUB_DISABLE_OS_PROBER=true\n')
    os.makedirs('/boot/grub', exist_ok=True)
    open('/boot/grub/grub.cfg', 'w').close()


def esp(with_shim=True):
    open('/etc/fstab', 'w').write('UUID=0B1C-2D3E /boot/efi vfat umask=0077 0 1\n')
    os.makedirs('/boot/efi', exist_ok=True)
    if with_shim:
        os.makedirs('/boot/efi/EFI/debian', exist_ok=True)
        for f in ('shimx64.efi', 'mmx64.efi', 'grubx64.efi'):
            open('/boot/efi/EFI/debian/' + f, 'w').write(f + '\n')


def main():
    os.environ['LANG'] = 'C.UTF-8'
    if CASE == 'update-grub-fails':
        grub_setup()
        stub('/usr/sbin/update-grub', '[ -e /tmp/update-grub-works ] && exit 0\necho "error: fake update-grub failure for the test" >&2\nexit 1')
        r = sh(['dpkg', '-i', DEB], check=False)
        out = r.stdout + r.stderr
        k = kept('update-grub')
        check(r.returncode != 0 and state() == 'iF', 'the package is not configured (dpkg exit %d, state %s)' % (r.returncode, state()))
        check('update-grub failed (exit status 1), so sparky-stereo-boot is not configured' in out and 'sudo dpkg --configure -a' in out,
              'what failed and what to do are said')
        check('fake update-grub failure for the test' in out, "update-grub's own error is shown")
        check(bool(k) and k['status'] == 1 and 'fake update-grub failure' in k['output'] and k['repair'] == [['update-grub']],
              'kept with its exit status, its output and the repair (%s)' % (k and k['status']))
        open('/tmp/update-grub-works', 'w').close()
        r = sh(['dpkg', '--configure', '-a'], check=False)
        check(r.returncode == 0 and state() == 'ii' and kept('update-grub') is None,
              'once update-grub works, dpkg --configure -a configures it and the problem is cleared (%s)' % state())
    elif CASE == 'esp-not-mounted':
        esp(with_shim=False)
        r = sh(['dpkg', '-i', DEB], check=False)
        out = r.stdout + r.stderr
        k = kept('esp-certificate')
        check(r.returncode == 0 and state() == 'ii', 'the package configures (this boot does not need the certificate) (%s)' % state())
        check('The EFI system partition /boot/efi is not mounted' in out and 'sudo mount /boot/efi' in out, 'said, with the mount to do')
        check(bool(k) and k['key'] == 'LOCAL23', 'kept for repair (%s)' % (k and k['key']))
        esp(with_shim=True)   # the partition is mounted now
        r = sh(['sparky-stereo-boot', 'repair'], check=False)
        check(r.returncode == 0 and os.path.isfile('/boot/efi/EFI/debian/sparky-stereo-secureboot-2026.der') and kept('esp-certificate') is None,
              'sparky-stereo-boot repair places the certificate and clears the problem (exit %d)' % r.returncode)
    elif CASE == 'hook-copy-fails':
        esp()
        sh(['dpkg', '-i', DEB])
        cert = '/boot/efi/EFI/debian/sparky-stereo-secureboot-2026.der'
        os.remove(cert)
        os.mkdir(cert)   # the copy onto it fails
        # the kernel's hooks, as linux-run-hooks runs them, with a marker after Debian's zz-update-grub
        hooks = '/tmp/postinst.d'
        os.makedirs(hooks)
        for h in ('zz-sparky-stereo-kernel-keep', 'zz-sparky-stereo-secureboot', 'zz-update-grub'):
            if os.path.exists('/etc/kernel/postinst.d/' + h):
                sh(['cp', '-a', '/etc/kernel/postinst.d/' + h, hooks])
        open(hooks + '/zzz-order345-marker', 'w').write('#!/bin/sh\ntouch /tmp/marker-ran\n')
        os.chmod(hooks + '/zzz-order345-marker', 0o755)
        r = sh(['run-parts', '--report', '--exit-on-error', '--arg=7.3.0-test', '--arg=/boot/vmlinuz-7.3.0-test', hooks],
               check=False, env=dict(os.environ, DEB_MAINT_PARAMS='configure', LANG='pt_BR.UTF-8'))
        out = r.stdout + r.stderr
        k = kept('esp-certificate')
        check(r.returncode == 0 and os.path.exists('/tmp/marker-ran'), 'the kernel installs: the hooks after it still run (exit %d)' % r.returncode)
        check(('O certificado do Secure Boot não pôde ser gravado em %s' % cert) in out and '(en) The Secure Boot certificate could not be written' in out,
              'said in the system language (pt_BR) and in English')
        check(bool(k) and k['key'] == 'LOCAL25' and cert in k['args'][0], 'kept for repair (%s)' % (k and k['args']))
    elif CASE in ('removal-fails', 'removal-fails-de'):
        grub_setup()
        sh(['dpkg', '-i', DEB])
        stub('/usr/sbin/update-initramfs', '[ -e /tmp/initramfs-works ] && exit 0\necho "E: fake update-initramfs failure for the test" >&2\nexit 1')
        head = '# GRUB Environment Block\nsparky_stereo_boot=plymouth.stereo=frame-packing\n'
        open('/boot/grub/grubenv', 'w').write(head + '#' * (1024 - len(head)))   # GRUB's 1024-byte block
        stub('/usr/bin/grub-editenv', '[ -e /tmp/grubenv-works ] && exit 0\necho "error: fake grub-editenv failure for the test" >&2\nexit 1')
        lang = 'de_DE.UTF-8' if CASE.endswith('-de') else 'C.UTF-8'
        r = sh(['dpkg', '-r', 'sparky-stereo-boot'], check=False, env=dict(os.environ, LANG=lang))
        out = r.stdout + r.stderr
        check(r.returncode != 0 and state() not in ('', 'un', 'rc'), 'the removal fails and dpkg keeps the package (exit %d, state %s)' % (r.returncode, state()))
        check('Removing sparky-stereo-boot: grub-editenv /boot/grub/grubenv unset sparky_stereo_boot failed (exit status 1)' in out
              and 'fake grub-editenv failure' in out, "GRUB's state that could not be cleared is said, with the tool's error")
        check('Removing sparky-stereo-boot: update-initramfs -u -k all failed (exit status 1)' in out and 'fake update-initramfs failure' in out,
              'the boot images that could not be rebuilt are said, with the tool\'s error')
        check('remove the package again' in out, 'what to do is said')
        if CASE.endswith('-de'):
            check('Entfernen von sparky-stereo-boot: update-initramfs -u -k all ist fehlgeschlagen (Exit-Status 1)' in out, 'in German')
        open('/tmp/initramfs-works', 'w').close()
        open('/tmp/grubenv-works', 'w').close()
        r = sh(['dpkg', '-r', 'sparky-stereo-boot'], check=False)
        check(r.returncode == 0 and state() == 'rc', 'once fixed, the removal runs again and completes (state %s)' % state())
    elif CASE == 'purge-update-grub-fails':
        grub_setup()
        stub('/usr/sbin/update-grub', '[ -e /tmp/update-grub-fails ] || exit 0\necho "error: fake update-grub failure for the test" >&2\nexit 1')
        sh(['dpkg', '-i', DEB])
        open('/tmp/update-grub-fails', 'w').close()
        r = sh(['dpkg', '-P', 'sparky-stereo-boot'], check=False)
        out = r.stdout + r.stderr
        check(r.returncode != 0 and state() not in ('', 'un'), 'the purge fails and dpkg keeps the package (exit %d, state %s)' % (r.returncode, state()))
        check('Removing sparky-stereo-boot: update-grub failed (exit status 1)' in out, 'said')
        os.remove('/tmp/update-grub-fails')
        r = sh(['dpkg', '-P', 'sparky-stereo-boot'], check=False)
        check(r.returncode == 0 and state() in ('', 'un'), 'once fixed, the purge completes (state %s)' % (state() or 'none'))
    else:
        raise SystemExit('unknown case ' + CASE)
    print('== %s: %s' % (CASE, 'ALL PASS' if all(results) else '%d FAILED' % results.count(False)))
    sys.exit(0 if all(results) else 1)


if __name__ == '__main__':
    main()
