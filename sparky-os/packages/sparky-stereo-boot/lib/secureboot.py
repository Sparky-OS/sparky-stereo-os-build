#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/03
"""The Sparky Stereo OS key and this computer's DKMS key on an installed system, for Secure Boot.

  secureboot.py esp       keep the edition's public certificate, and this computer's DKMS certificate, next to every
                          shim on the EFI system partition
  secureboot.py grub      write the GRUB menu entries that enroll them (run by /etc/grub.d/35_sparky_stereo_secureboot)
  secureboot.py dkms-key  esp, then under Secure Boot say and keep a DKMS key that is not enrolled while modules signed
                          with it are installed (sparky-stereo-boot-secureboot.service: at every boot, and when DKMS
                          makes its key, sparky-stereo-boot-dkms-key.path)

The edition's kernels are signed with the Sparky Stereo OS key. Under Secure Boot, Debian's shim starts them only
when that key is in the firmware's MOK list, and a new or reset motherboard, or Secure Boot turned on after the
installation, leaves the list without it: GRUB then refuses the kernel ("bad shim loader signature",
grub-core/kern/efi/sb.c) and the system does not start. So the certificate stays on the EFI system partition beside
each shim and MokManager (mmx64.efi, which shim's packages install beside it), and GRUB's menu has an entry that shows
the steps in the nine required languages and starts that MokManager: "Enroll key from disk" enrolls the certificate
from the partition with a confirmation, no password (MokManager.c, enroll_file). When Secure Boot is on (GRUB sets
shim_lock=y, grub_shim_lock_verifier_setup), the menu first asks shim about the newest edition kernel (GRUB's linux
command verifies it); if shim refuses it, the enrolment entry becomes the menu's default, so the timeout starts it
and the person sees it selected. (GRUB's fallback takes entry numbers only, get_and_remove_first_entry_number in
grub-core/normal/menu.c, and the number of entries before this one is not known here.)
A certificate that cannot be placed is said and kept for repair (problems.py, step esp-certificate): the EFI system
partition named in /etc/fstab but not mounted, the certificate missing from the package, a copy that fails. That does
not stop a package or a kernel from installing: the boot of this system does not need the certificate today, and a
failing kernel hook would keep zz-update-grub from writing the new kernel's menu entry. A machine with no EFI system
partition (a BIOS boot) has nothing to place, as shim-signed's postinst skips such a machine; an EFI system partition
without shim is said, since GRUB's menu then has no enrolment entry.
This computer's DKMS modules (drivers built on it, such as NVIDIA's) are signed with its own key, which DKMS makes
the first time it signs (/var/lib/dkms/mok.pub, DER, or mok_certificate in dkms's framework configuration). Secure
Boot loads them only when that key is in the MOK list too, and no package enrolls it (Debian #1076269; dkms-project/dkms
#429, closed as stale). So its certificate follows the same design as the edition's (ORDER 374): kept next to every
shim as dkms-this-computer.der, removed when the computer has no DKMS key, and a second GRUB entry, "Secure Boot:
enroll this computer's DKMS key", in the system's language, shown when the certificate is on the partition (GRUB looks
for it when the menu is read, so a key DKMS makes later needs no update-grub). Under Secure Boot, a DKMS key that is
not enrolled while modules signed with it are installed for the running kernel is said and kept, naming that entry,
until it is enrolled.
Environment: SPARKY_STEREO_ESP (default /boot/efi), SPARKY_STEREO_CERT (default the packaged certificate),
SPARKY_STEREO_LANG_DIR (default /usr/share/sparky/sparky-stereo-boot), SPARKY_STEREO_FSTAB (default /etc/fstab),
SPARKY_STEREO_DKMS_CERT (default dkms's mok_certificate), SPARKY_STEREO_EFI (default /sys/firmware/efi),
SPARKY_STEREO_KERNEL (default the running kernel's release), LANG;
from the grub.d script:
SPARKY_STEREO_KERNEL_PATH (the kernel as GRUB reaches it), SPARKY_STEREO_KERNEL_ACCESS (GRUB's lines to reach its
file system, grub-mkconfig_lib's prepare_grub_to_access_device) and SPARKY_STEREO_ESP_UUID (the partition's).
"""
import filecmp
import os
import shutil
import struct
import subprocess
import sys
import unicodedata
from uuid import UUID

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import problems  # noqa: E402

CERT_NAME = 'sparky-stereo-secureboot-2026.der'
CERT = os.environ.get('SPARKY_STEREO_CERT', '/usr/share/sparky-stereo-boot/secureboot/' + CERT_NAME)
ESP = os.environ.get('SPARKY_STEREO_ESP', '/boot/efi')
LANG_DIR = os.environ.get('SPARKY_STEREO_LANG_DIR', '/usr/share/sparky/sparky-stereo-boot')
FSTAB = os.environ.get('SPARKY_STEREO_FSTAB', '/etc/fstab')
STEP = 'esp-certificate'
REPAIR = [['python3', '/usr/lib/sparky-stereo-boot/secureboot.py', 'esp']]
DKMS_NAME = 'dkms-this-computer.der'
DKMS_STEP = 'esp-dkms-certificate'
ENROL_STEP = 'dkms-key-enrolment'
EFI = os.environ.get('SPARKY_STEREO_EFI', '/sys/firmware/efi')
EFI_GLOBAL = '8be4df61-93ca-11d2-aa0d-00e098032b8c'
SHIM_LOCK = '605dab50-e046-4300-abb6-3dd810dd8b23'
CERT_X509 = UUID('a5c059a1-94e4-4aa7-87b5-ab155c2bf072').bytes_le   # EFI_CERT_X509_GUID
LANGS = ['en', 'pl', 'pt_BR', 'fr', 'de', 'es', 'ja', 'ko', 'zh_CN', 'zh_TW']
COLUMNS = 98   # GRUB's terminal at 800x600 with Unifont 16 has 100 columns; wider screens have more


def efi_dirs():
    """The folders of the EFI system partition that hold shim: EFI/<id>/shimx64.efi, and the removable-media path
    (EFI/BOOT/BOOTX64.EFI) when it is a copy of one of them."""
    root = os.path.join(ESP, 'EFI')
    if not os.path.isdir(root):
        return []
    found, shims = [], []
    for d in sorted(os.listdir(root)):
        p = os.path.join(root, d)
        for f in os.listdir(p) if os.path.isdir(p) else []:
            if f.lower() == 'shimx64.efi':
                found.append(p)
                shims.append(os.path.join(p, f))
    for d in sorted(os.listdir(root)):
        p = os.path.join(root, d)
        for f in os.listdir(p) if os.path.isdir(p) and d.lower() == 'boot' else []:
            if f.lower() == 'bootx64.efi' and any(filecmp.cmp(os.path.join(p, f), s, shallow=False) for s in shims):
                found.append(p)
    return found


def esp_declared():
    """The EFI system partition is this system's: /etc/fstab mounts something at ESP."""
    want = os.path.normpath(ESP)
    try:
        for line in open(FSTAB, encoding='utf-8', errors='replace'):
            fields = line.split()
            if len(fields) >= 2 and not fields[0].startswith('#') and os.path.normpath(fields[1]) == want:
                return True
    except OSError:
        pass
    return False


def esp(quiet=False):
    """Copy the certificate next to every shim; returns the folders that hold it and whether it failed somewhere."""
    if not os.path.isfile(CERT):
        problems.record(STEP, 'LOCAL24', [CERT], repair=[['apt-get', 'install', '--reinstall', 'sparky-stereo-boot']])
        return [], True
    if not os.path.isdir(os.path.join(ESP, 'EFI')):
        if esp_declared() and not os.path.ismount(ESP):
            problems.record(STEP, 'LOCAL23', [ESP, ESP], repair=REPAIR)
            return [], True
        if os.path.ismount(ESP):
            problems.say('LOCAL26', [ESP])
        problems.clear(STEP)
        return [], False
    dirs = efi_dirs()
    if not dirs:
        problems.say('LOCAL26', [ESP])
        problems.clear(STEP)
        return [], False
    held, failed = [], []
    for d in dirs:
        target = os.path.join(d, CERT_NAME)
        try:
            if not (os.path.isfile(target) and filecmp.cmp(CERT, target, shallow=False)):
                shutil.copyfile(CERT, target)
                if not quiet:
                    print('sparky-stereo-boot: %s' % target)
            held.append(d)
        except OSError as e:
            failed.append((target, e.strerror or str(e)))
    if failed:
        problems.record(STEP, 'LOCAL25', [', '.join(t for t, _ in failed), '; '.join(sorted({e for _, e in failed}))],
                        repair=REPAIR)
    else:
        problems.clear(STEP)
    return held, esp_dkms(dirs, quiet) or bool(failed)


def dkms_framework():
    """mok_certificate and dkms_tree as dkms reads them from its framework configuration (read_framework_conf:
    /etc/dkms/framework.conf, then framework.conf.d/*.conf), else DKMS's defaults."""
    script = ('mok_certificate=; dkms_tree=; for f in /etc/dkms/framework.conf /etc/dkms/framework.conf.d/*.conf; do '
              '[ -e "$f" ] && . "$f" >/dev/null 2>&1; done; printf "%s\\n%s\\n" "$mok_certificate" "$dkms_tree"')
    try:
        lines = subprocess.run(['sh', '-c', script], stdin=subprocess.DEVNULL, capture_output=True, text=True,
                               timeout=30).stdout.split('\n')
    except (OSError, subprocess.SubprocessError):
        lines = []
    lines += ['', '']
    return {'mok_certificate': os.environ.get('SPARKY_STEREO_DKMS_CERT') or lines[0].strip() or '/var/lib/dkms/mok.pub',
            'dkms_tree': os.environ.get('SPARKY_STEREO_DKMS_TREE') or lines[1].strip() or '/var/lib/dkms'}


def dkms_certificate():
    """This computer's DKMS certificate."""
    return dkms_framework()['mok_certificate']


def dkms_der():
    """(path, DER bytes or None, why it cannot be read or None): MokManager enrolls a DER certificate; DKMS writes
    its own as DER (prepare_mok: openssl req -outform DER), and one configured as PEM is converted."""
    path = dkms_certificate()
    try:
        data = open(path, 'rb').read()
    except FileNotFoundError:
        return path, None, None
    except OSError as e:
        return path, None, e.strerror or str(e)
    if data[:1] == b'\x30':
        return path, data, None
    if b'-----BEGIN CERTIFICATE-----' in data:
        try:
            out = subprocess.run(['openssl', 'x509', '-in', path, '-outform', 'DER'], stdin=subprocess.DEVNULL,
                                 capture_output=True, timeout=30)
        except (OSError, subprocess.SubprocessError) as e:
            return path, None, str(e)
        if out.returncode == 0 and out.stdout[:1] == b'\x30':
            return path, out.stdout, None
        return path, None, (out.stderr.decode('utf-8', 'replace').strip().splitlines() or ['openssl x509'])[-1]
    return path, None, 'not DER or PEM'


def esp_dkms(dirs, quiet=False):
    """This computer's DKMS certificate as DKMS_NAME next to every shim, or no copy there when the computer has no
    DKMS key (nothing to enroll); True when it failed somewhere (said and kept as DKMS_STEP)."""
    path, der, why = dkms_der()
    if why:
        problems.record(DKMS_STEP, 'LOCAL65', [path, why], repair=REPAIR)
        return True
    failed = []
    for d in dirs:
        target = os.path.join(d, DKMS_NAME)
        try:
            if der is None:
                if os.path.lexists(target):
                    os.remove(target)
                    if not quiet:
                        print('sparky-stereo-boot: %s removed' % target)
                continue
            try:
                same = open(target, 'rb').read() == der
            except FileNotFoundError:
                same = False
            if not same:
                with open(target + '.new', 'wb') as f:
                    f.write(der)
                os.replace(target + '.new', target)
                if not quiet:
                    print('sparky-stereo-boot: %s' % target)
        except OSError as e:
            failed.append((target, e.strerror or str(e)))
    if failed:
        problems.record(DKMS_STEP, 'LOCAL64', [', '.join(t for t, _ in failed), '; '.join(sorted({e for _, e in failed}))],
                        repair=REPAIR)
        return True
    problems.clear(DKMS_STEP)
    return False


def efivar(name, guid):
    """An EFI variable's data (efivarfs puts its attributes first, 4 bytes), or None."""
    try:
        return open(os.path.join(EFI, 'efivars', '%s-%s' % (name, guid)), 'rb').read()[4:]
    except OSError:
        return None


def secure_boot():
    value = efivar('SecureBoot', EFI_GLOBAL)
    return bool(value) and value[0] == 1


def mok_list():
    """The DER certificates in shim's MokListRT, or None when it cannot be read: the kernel's copy of shim's MOK
    configuration table (/sys/firmware/efi/mok-variables, drivers/firmware/efi/mokvar-table.c), else the runtime
    variable. Each is an EFI_SIGNATURE_LIST (UEFI 2.10, 32.4.1) of EFI_CERT_X509_GUID entries."""
    try:
        data = open(os.path.join(EFI, 'mok-variables', 'MokListRT'), 'rb').read()
    except OSError:
        data = efivar('MokListRT', SHIM_LOCK)
    if data is None:
        return None
    certs, pos = [], 0
    while pos + 28 <= len(data):
        kind = data[pos:pos + 16]
        size, header, each = struct.unpack('<III', data[pos + 16:pos + 28])
        if size < 28 or pos + size > len(data):
            break
        body = data[pos + 28 + header:pos + size]
        if kind == CERT_X509 and each > 16:
            for i in range(0, len(body) - each + 1, each):
                certs.append(body[i + 16:i + each])   # the owner's GUID first
        pos += size
    return certs


def der_serial(der):
    """The serial number of a DER certificate (RFC 5280, 4.1) as modinfo prints a module's sig_key: hex in capitals,
    without leading zeros."""
    def value(i):
        """(start, end) of the value of the DER element at I."""
        n = der[i + 1]
        i += 2
        if n & 0x80:
            k = n & 0x7f
            n = int.from_bytes(der[i:i + k], 'big')
            i += k
        return i, i + n
    tbs, _ = value(0)                  # Certificate ::= SEQUENCE { tbsCertificate, ... }
    first, _ = value(tbs)              # TBSCertificate ::= SEQUENCE { version [0] DEFAULT v1, serialNumber, ... }
    start, end = value(first)
    if der[first] == 0xa0:
        start, end = value(end)
    return der[start:end].hex().upper().lstrip('0')


def modules_signed_with(serial, kernel):
    """MODULE/VERSION of the DKMS modules installed for KERNEL whose file the kernel loads is signed with the key of
    SERIAL (modinfo's sig_key)."""
    tree = dkms_framework()['dkms_tree']
    found = []
    try:
        modules = sorted(os.listdir(tree))
    except OSError:
        return found
    for module in modules:
        try:
            links = [l for l in os.listdir(os.path.join(tree, module)) if l.startswith('kernel-%s-' % kernel)]
        except OSError:
            continue
        for link in links:
            build = os.path.realpath(os.path.join(tree, module, link))
            try:
                files = sorted(f for f in os.listdir(os.path.join(build, 'module')) if '.ko' in f)
            except OSError:
                continue
            for f in files:
                name = f.split('.ko')[0]
                loaded = run_text(['modinfo', '-k', kernel, '-n', name]) or os.path.join(build, 'module', f)
                key = run_text(['modinfo', '-F', 'sig_key', loaded if os.path.isfile(loaded) else os.path.join(build, 'module', f)])
                if key.replace(':', '').upper().lstrip('0') == serial:
                    found.append('%s/%s' % (module, os.path.basename(os.path.dirname(os.path.dirname(build)))))
                    break
    return sorted(set(found))


def run_text(command):
    try:
        out = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return ''
    return out.stdout.strip() if out.returncode == 0 else ''


def enrolment():
    """Under Secure Boot, this computer's DKMS key not in the MOK list while modules signed with it are installed for
    the running kernel: said and kept, naming GRUB's entry that enrolls it, until it is enrolled."""
    if not secure_boot():
        problems.clear(ENROL_STEP)
        return
    _, der, _ = dkms_der()
    certs = mok_list()
    if der is None or (certs is not None and der in certs):
        problems.clear(ENROL_STEP)
        return
    if certs is None:
        return   # shim's list cannot be read: nothing known to say
    kernel = os.environ.get('SPARKY_STEREO_KERNEL') or os.uname().release
    modules = modules_signed_with(der_serial(der), kernel)
    if not modules:
        problems.clear(ENROL_STEP)
        return
    problems.record(ENROL_STEP, 'LOCAL66', [', '.join(modules), ['LOCAL62']])


def dkms_key():
    """At every boot and when DKMS makes its key: the certificates on the EFI system partition, then the enrolment."""
    failed = esp()[1]
    enrolment()
    return failed


def strings(lang):
    values = {}
    try:
        for line in open(os.path.join(LANG_DIR, lang), encoding='utf-8'):
            if '=' in line:
                k, v = line.rstrip('\n').split('=', 1)
                values[k] = v.strip().strip('"')
    except OSError:
        pass
    return values


def system_lang():
    lang = os.environ.get('LANG', '')
    if not lang:
        try:
            for line in open('/etc/default/locale', encoding='utf-8'):
                if line.startswith('LANG='):
                    lang = line.split('=', 1)[1].strip().strip('"')
        except OSError:
            pass
    lang = lang.split('.')[0]
    for c in ([lang, 'zh_CN'] if lang.startswith('zh') else [lang, lang.split('_')[0]]):
        if c in LANGS:
            return c
    return 'en'


def os_id():
    try:
        for line in open(os.environ.get('SPARKY_STEREO_OS_RELEASE', '/etc/os-release'), encoding='utf-8'):
            if line.startswith('ID='):
                return line.split('=', 1)[1].strip().strip('"').lower()
    except OSError:
        pass
    return ''


def width(text):
    return sum(2 if unicodedata.east_asian_width(c) in 'WF' else 1 for c in text)


def wrap(text, columns=COLUMNS):
    """Lines of at most COLUMNS display columns: at spaces, and anywhere inside CJK text."""
    lines, line = [], ''
    for word in text.split(' '):
        piece = (line + ' ' + word) if line else word
        if width(piece) <= columns:
            line = piece
            continue
        if line:
            lines.append(line)
        line = ''
        for c in word:
            if width(line + c) > columns:
                lines.append(line)
                line = ''
            line += c
    if line:
        lines.append(line)
    return lines


def quote(text):
    """TEXT as one GRUB word: in single quotes, or in double quotes when it has an apostrophe (English's "computer's"),
    with what GRUB expands there escaped (grub-core/script/yylex.l)."""
    if "'" not in text:
        return "'%s'" % text
    return '"%s"' % text.replace('\\', '\\\\').replace('"', '\\"').replace('$', '\\$')


def steps(order, key, folder):
    """The echo lines of KEY's steps, in each language of ORDER, wrapped for GRUB's terminal."""
    out = []
    for lang in order:
        s = strings(lang)
        text = s.get(key)
        if not text:
            continue
        for line in wrap('%s: %s' % (s.get('LOCAL14', lang), text.replace('{folder}', folder))):
            out.append('            echo "%s"' % line.replace('"', '').replace('$', '').replace('\\', ''))
    return out


def grub():
    held, _ = esp(quiet=True)
    if not held:
        return   # no shim on an EFI system partition here (a BIOS boot, or another boot loader)
    # the system's own folder (os-release ID, as grub-install names it), else the first that is not EFI/BOOT;
    # the certificate is in each of them
    names = [os.path.basename(d) for d in held]
    folder = next((n for n in names if n.lower() == os_id()), None) or next((n for n in names if n.lower() != 'boot'), names[0])
    first = system_lang()
    order = [first] + [lang for lang in LANGS if lang != first]
    own, english = strings(first), strings('en')
    title = own.get('LOCAL12') or english.get('LOCAL12', 'Secure Boot: enroll the Sparky Stereo OS key')
    dkms_title = own.get('LOCAL62') or english.get('LOCAL62', "Secure Boot: enroll this computer's DKMS key")
    # MokManager beside shim in the system's folder: the partition by its UUID, else by the file (GRUB's cmdpath is not
    # exported into the configfile that reads this menu, so it cannot name the folder GRUB came from)
    uuid = os.environ.get('SPARKY_STEREO_ESP_UUID', '')
    mm = '/EFI/%s/mmx64.efi' % folder
    find = ['            set sparky_mm=',
            '            search --no-floppy --file --set=sparky_mm %s' % mm]
    if uuid:
        find = ['            set sparky_mm=',
                '            search --no-floppy --fs-uuid --set=sparky_mm %s' % uuid,
                '            if [ -z "$sparky_mm" ]; then',
                '                search --no-floppy --file --set=sparky_mm %s' % mm,
                '            fi']
    start = ['            sleep --interruptible --verbose 60'] + find + [
             '            terminal_output console',
             '            chainloader ($sparky_mm)%s' % mm,
             '        }']
    out = ['if [ "$grub_platform" = efi ]; then',
           '    if [ "$grub_cpu" = x86_64 ]; then',
           "        menuentry '%s' --id sparky-enroll {" % title.replace("'", '')]
    out += steps(order, 'LOCAL13', folder) + start
    # this computer's DKMS key: the entry is there when its certificate is on the partition. With the partition's UUID
    # GRUB looks for the certificate when it reads the menu, so a key DKMS makes later (the first boot's signing) needs
    # no update-grub; without it (the partition not mounted at update-grub), the entry follows what update-grub finds.
    dkms = ['        menuentry %s --id sparky-enroll-dkms {' % quote(dkms_title)]
    dkms += steps(order, 'LOCAL63', folder) + start
    cert = '/EFI/%s/%s' % (folder, DKMS_NAME)
    if uuid:
        out += ['        set sparky_dkms=',
                '        search --no-floppy --fs-uuid --set=sparky_dkms %s' % uuid,
                '        if [ -n "$sparky_dkms" ]; then',
                '            if [ -f "($sparky_dkms)%s" ]; then' % cert]
        out += ['        ' + line for line in dkms]
        out += ['            fi',
                '        fi']
    elif any(os.path.isfile(os.path.join(d, DKMS_NAME)) for d in held if os.path.basename(d) == folder):
        out += dkms
    path = os.environ.get('SPARKY_STEREO_KERNEL_PATH')
    if path:
        access = [l.strip() for l in os.environ.get('SPARKY_STEREO_KERNEL_ACCESS', '').splitlines() if l.strip()]
        out += ['        if [ "$shim_lock" = y ]; then',
                '            set sparky_root="$root"',
                *['            ' + l for l in access],
                '            if linux %s; then' % path,
                '                true',
                '            else',
                '                set default=sparky-enroll',
                '            fi',
                '            set root="$sparky_root"',
                '        fi']
    out += ['    fi',
            'fi']
    print('\n'.join(out))


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ''
    if cmd == 'esp':
        sys.exit(1 if esp()[1] else 0)
    elif cmd == 'grub':
        grub()
    elif cmd == 'dkms-key':
        sys.exit(1 if dkms_key() else 0)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
