#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/27
# Copyright 2026 under the GNU GPL3 License
"""The anti-cheat start (sparky-stereo-boot 0.1.17, row 190), and what Easy Anti-Cheat Linux v2 would see.

Daniel, 2026-10-21: the anti-cheat boot entry is a one-time choice in Plasma's restart menu, like "restart to UEFI
firmware setup"; hibernation stays the default boot. Easy Anti-Cheat Linux v2 (Epic Online Services, "Awesome Gaming
on Linux Without Cheating", 2026-10-14) asks for a signed kernel and signed modules with a well-known Secure Boot key,
TPM 2.0, measured boot, the IOMMU on with passthrough off, kernel lockdown in integrity mode, kexec disabled at boot
time and the BPF LSM. The edition's usual start keeps hibernation, so it has no lockdown (memory kernel-is-the-soul,
2026-10-08: "lockdown only as a boot option"); Epic's FAQ allows exactly that: "You can maintain a separate boot entry
with the required kernel and command line, and select that entry when you want to play a protected game."

  grub_entry()          update-grub (/etc/grub.d/89_sparky_stereo_anticheat): Debian's own 10_linux entry for the
                        newest kernel, again, with the anti-cheat kernel line, under its own id; and the file that
                        says it can be started once (ENTRY_FILE), kept only when GRUB can be told to
  restart('set')        root (pkexec, polkit action org.sparkystereo.boot.restart-for-anti-cheat): the next start is
                        the anti-cheat start, once: GRUB's own grub-reboot where GRUB can write /boot/grub, else the
                        edition's environment block on the EFI system partition (read by the same GRUB script)
  restart('unset')      root: a request of ours that was not used is taken back (a cancelled logout)
  check()               what Easy Anti-Cheat would see, requirement by requirement: met, not met or unknown, and why
  anticheat_start()     at the anti-cheat start: the session is told that hibernation is off until the next restart

The kernel line of the anti-cheat start, each with its source (Linux 7.3, Documentation/admin-guide/kernel-parameters
.txt, unless named):
  lockdown=integrity                       "kernel features that allow userland to modify the running kernel are
                                           disabled"; LOCKDOWN_HIBERNATION is below LOCKDOWN_INTEGRITY_MAX
                                           (include/linux/security.h), so hibernation_available() is false
                                           (kernel/power/hibernate.c)
  sysctl.kernel.kexec_load_disabled=1      set "right before loading the init process" (sysctl.*=); with it
                                           kexec_load_permitted() refuses kexec_load and kexec_file_load
                                           (kernel/kexec_core.c)
  nohibernate                              hibernation and resume off (nohibernate_setup sets nohibernate and
                                           noresume), whatever lockdown does
  intel_iommu=on iommu.passthrough=0       the IOMMU on where Intel's is off by default (CONFIG_INTEL_IOMMU_DEFAULT_ON
                                           is not set in the edition's kernels; AMD's is on when the firmware has it)
                                           and devices translated, not passed through
  sparky_stereo.anticheat=1                the edition's mark: the initramfs guard and the login notice read it
  lsm=...,bpf                              only when the person's kernel line has an lsm= without bpf (the edition's
                                           CONFIG_LSM has bpf)
"""
import base64
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import uuid

ROOT = os.environ.get('SPARKY_STEREO_ROOT', '')
STATE_DIR = ROOT + '/var/lib/sparky-stereo-boot'
ENTRY_FILE = STATE_DIR + '/anticheat.entry'
RUN_DIR = ROOT + '/run/sparky-stereo-boot'
ONCE_FILE = RUN_DIR + '/anticheat-once'
ENTRY_ID = 'gnulinux-sparky-stereo-anticheat'
GRUBENV = ROOT + '/boot/grub/grubenv'
GRUB_CFG = ROOT + '/boot/grub/grub.cfg'
ESP = ROOT + os.environ.get('SPARKY_STEREO_ESP', '/boot/efi')
ESP_BLOCK = '/EFI/sparky-stereo-boot/grubenv'
ESP_VARIABLE = 'sparky_anticheat_once'
EFI = ROOT + '/sys/firmware/efi'
EFIVARS = EFI + '/efivars'
CMDLINE = ROOT + '/proc/cmdline'
SECURITYFS = ROOT + '/sys/kernel/security'
SYSFS = ROOT + '/sys'
PROC = ROOT + '/proc'
CONFIG = ROOT + '/etc/default/sparky-stereo-boot'
LANG_DIR = os.environ.get('SPARKY_STEREO_LANG_DIR', '/usr/share/sparky/sparky-stereo-boot')
EDITION_CERT = os.environ.get('SPARKY_STEREO_EDITION_CERT',
                              '/usr/share/sparky-stereo-boot/secureboot/sparky-stereo-secureboot-2026.der')
DKMS_CERT = ROOT + '/var/lib/dkms/mok.pub'
ARGS = ['lockdown=integrity', 'sysctl.kernel.kexec_load_disabled=1', 'nohibernate', 'intel_iommu=on',
        'iommu.passthrough=0', 'sparky_stereo.anticheat=1']
MARK = 'sparky_stereo.anticheat=1'
# Debian's own check_writable (00_header): GRUB cannot write through these
NOT_WRITABLE_ABSTRACTIONS = ('diskfilter', 'lvm')
NOT_WRITABLE_FS = ('btrfs', 'cpiofs', 'newc', 'odc', 'romfs', 'squash4', 'tarfs', 'zfs')
EFI_GLOBAL = '8be4df61-93ca-11d2-aa0d-00e098032b8c'
SHIM_LOCK = '605dab50-e046-4300-abb6-3dd810dd8b23'
X509_GUID = uuid.UUID('a5c059a1-94e4-4aa7-87b5-ab155c2bf072').bytes_le
# TCG PC Client Platform Firmware Profile: EV_EFI_BOOT_SERVICES_APPLICATION, the measurement of a boot manager (shim,
# GRUB) that the firmware loaded, extended into PCR 4
EV_EFI_BOOT_SERVICES_APPLICATION = 0x80000003
TPM_ALG_DIGEST_SIZES = {0x0004: 20, 0x000b: 32, 0x000c: 48, 0x000d: 64, 0x0012: 32}
# The boot manager's own measurements: GRUB's commands and files in PCRs 8 and 9, systemd-boot's and systemd-stub's in 11
# and 12 (the rule of Bazzite's check-anticheat, Universal Blue, Apache-2.0)
BOOT_MANAGER_PCRS = (8, 9, 11, 12)
# The signing keys Epic's announcement of 2026-10-14 names as well-known, as certificate names (Bazzite's check-anticheat
# reads the same list from the same page); a certificate is on the list when its subject or its issuer names one
WELL_KNOWN = re.compile(r'Canonical Ltd\. Master Certificate Authority|Fedora Secure Boot CA|Universal Blue|'
                        r'Debian Secure Boot CA|openSUSE Secure Boot CA|SUSE Linux Enterprise Secure Boot CA|'
                        r'Rocky Linux Secure Boot Root CA|Microsoft (Corporation )?UEFI CA|AlmaLinux Secure Boot CA')
TAINT_UNSIGNED_MODULE = 1 << 13


# ------------------------------------------------------------------ the package's language files (Paweł's LOCAL files)
def _language():
    lang = os.environ.get('LANG', '')
    if not lang:
        try:
            for line in open(ROOT + '/etc/default/locale', encoding='utf-8'):
                if line.startswith('LANG='):
                    lang = line.split('=', 1)[1].strip().strip('"')
        except OSError:
            pass
    return lang.split('.')[0]


def strings(lang=None):
    lang = _language() if lang is None else lang
    candidates = [lang, lang.split('_')[0], 'en']
    if lang.startswith('zh'):
        candidates = [lang, 'zh_CN', 'en']
    english = {}
    chosen = None
    for code in candidates + ['en']:
        path = os.path.join(LANG_DIR, code)
        if not code or not os.path.isfile(path):
            continue
        values = {}
        for line in open(path, encoding='utf-8'):
            line = line.strip()
            if '=' in line and not line.startswith('#'):
                key, value = line.split('=', 1)
                values[key.strip()] = value.strip().strip('"')
        if code == 'en':
            english = values
        if chosen is None:
            chosen = values
    merged = dict(english)
    merged.update(chosen or {})
    return merged


def text(values, key, *args):
    template = values.get(key, key)
    try:
        return template % args if args else template
    except (TypeError, ValueError):
        return template + ' ' + ' '.join(str(a) for a in args)


def say(key, *args):
    """A line for the person who runs it, in their language, and in English after it when that differs."""
    message = text(strings(), key, *args)
    print('sparky-stereo-boot: ' + message, file=sys.stderr, flush=True)
    english = text(strings('en'), key, *args)
    if english != message:
        print('sparky-stereo-boot: ' + english, file=sys.stderr, flush=True)


# ------------------------------------------------------------------ small readers
def _read(path, mode='r'):
    try:
        with open(path, mode) as handle:
            return handle.read()
    except OSError:
        return None


def _cmdline():
    return (_read(CMDLINE) or '').split()


def _option(name, default):
    value = default
    try:
        for line in open(CONFIG, encoding='utf-8'):
            line = line.strip()
            if line.startswith(name + '='):
                value = line.split('=', 1)[1].strip().strip('"').strip("'")
    except OSError:
        pass
    return value


def _efivar(name, guid):
    data = _read(os.path.join(EFIVARS, '%s-%s' % (name, guid)), 'rb')
    return None if data is None else data[4:]


def _atomic_write(path, content, mode=0o644):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix='.' + os.path.basename(path))
    with os.fdopen(fd, 'w', encoding='utf-8') as handle:
        handle.write(content)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def _run(command, **kw):
    return subprocess.run(command, capture_output=True, text=True, timeout=kw.pop('timeout', 60), **kw)


def _tool(name):
    """A tool by its full path: a desktop session's PATH has no sbin, where kmod puts modinfo."""
    for folder in os.environ.get('PATH', '').split(':') + ['/usr/sbin', '/sbin', '/usr/bin', '/bin']:
        if folder and os.access(os.path.join(folder, name), os.X_OK):
            return os.path.join(folder, name)
    return name


# ------------------------------------------------------------------ where GRUB can keep a one-time request
def grub_place():
    """('grubenv', None), ('esp', 'UUID'), or ('none', why). Debian's own rule for /boot/grub (check_writable in
    00_header) and the edition's environment block on the EFI system partition where GRUB cannot write there, as
    30-sparky-stereo-boot.cfg decides for its record of a start."""
    probe = os.environ.get('SPARKY_GRUB_PROBE', 'grub-probe')
    why = None
    try:
        abstraction = _run([probe, '--target=abstraction', ROOT + '/boot/grub'])
        fs = _run([probe, '--target=fs', ROOT + '/boot/grub'])
        if abstraction.returncode or fs.returncode:
            why = 'grub-probe: ' + (abstraction.stderr or fs.stderr).strip()
        else:
            for name in abstraction.stdout.split():
                if name in NOT_WRITABLE_ABSTRACTIONS:
                    why = name
            if fs.stdout.strip() in NOT_WRITABLE_FS:
                why = fs.stdout.strip()
    except (OSError, subprocess.SubprocessError) as error:
        why = 'grub-probe: %s' % error
    if why is None:
        return 'grubenv', None
    esp_mounted = os.path.isdir(ESP) if ROOT else os.path.ismount(ESP)
    if os.path.isdir(EFI) and esp_mounted:
        try:
            if (_run([probe, '--target=fs', ESP]).stdout.strip() == 'fat'
                    and not _run([probe, '--target=abstraction', ESP]).stdout.strip()):
                fs_uuid = _run([probe, '--target=fs_uuid', ESP]).stdout.strip()
                block = ESP + ESP_BLOCK
                if fs_uuid and (os.path.getsize(block) if os.path.exists(block) else 0) == 0:
                    os.makedirs(os.path.dirname(block), exist_ok=True)
                    if os.path.exists(block):
                        os.remove(block)
                    _run([os.environ.get('SPARKY_GRUB_EDITENV', 'grub-editenv'), block, 'create'])
                if fs_uuid and os.path.exists(block):
                    return 'esp', fs_uuid
        except (OSError, subprocess.SubprocessError):
            pass
    return 'none', why


def _entry_state():
    values = {}
    for line in (_read(ENTRY_FILE) or '').splitlines():
        if '=' in line:
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip()
    return values


# ------------------------------------------------------------------ the GRUB entry (update-grub)
def _grub_quote(value):
    return "'" + value.replace("'", "'\\''") + "'"


def _kernel_args(cmdline):
    """The anti-cheat arguments for a kernel line that already has CMDLINE: lsm= gains bpf only when the person's own
    lsm= leaves it out (the last lsm= is the one the kernel keeps: security/security.c, choose_lsm_order)."""
    args = list(ARGS)
    lsm = [a.split('=', 1)[1] for a in cmdline.split() if a.startswith('lsm=')]
    if lsm and 'bpf' not in lsm[-1].split(','):
        args.append('lsm=%s,bpf' % lsm[-1])
    return args


def make_entry(linux_output, title_key_values):
    """From the output of Debian's 10_linux: its first entry (the newest kernel's, as the menu's default), renamed and
    under the anti-cheat id. None when the output has no entry this can use."""
    lines = linux_output.splitlines()
    start = next((i for i, line in enumerate(lines) if re.match(r"^menuentry '", line)), None)
    if start is None:
        return None, None
    end = next((i for i in range(start + 1, len(lines)) if lines[i] == '}'), None)
    if end is None:
        return None, None
    entry = lines[start:end + 1]
    head = re.match(r"^menuentry '((?:[^']|'\\'')*)'(.*)\$menuentry_id_option '[^']*'(.*)\{$", entry[0])
    if not head:
        return None, None
    title = head.group(1).replace("'\\''", "'")
    entry[0] = 'menuentry %s%s$menuentry_id_option %s%s{' % (
        _grub_quote(text(title_key_values, 'LOCAL110', title)), head.group(2), _grub_quote(ENTRY_ID), head.group(3))
    kernel = None
    for line in entry:
        found = re.match(r"^\s*linux\s+(\S+)\s", line)
        if found:
            kernel = os.path.basename(found.group(1)).replace('vmlinuz-', '', 1)
            if ' lockdown=integrity' not in line:
                return None, None
    if kernel is None:
        return None, None
    return '\n'.join(entry) + '\n', kernel


def grub_entry():
    """Writes the anti-cheat entry on stdout (grub-mkconfig takes it), and keeps ENTRY_FILE only when the one-time
    restart can reach it. Every case is said; a menu without the entry is a problem kept until repaired."""
    sys.path.insert(0, os.environ.get('SPARKY_STEREO_LIB', '/usr/lib/sparky-stereo-boot'))
    import problems
    try:
        os.remove(ENTRY_FILE)
    except OSError:
        pass
    if _option('SPARKY_STEREO_ANTICHEAT', 'yes') == 'no':
        problems.clear('anticheat-entry')
        say('LOCAL108')
        return 0
    if not os.path.isdir(EFI):
        problems.clear('anticheat-entry')
        say('LOCAL107')
        return 0
    linux = os.environ.get('SPARKY_GRUB_10_LINUX', '/etc/grub.d/10_linux')
    env = dict(os.environ)
    cmdline = '%s %s' % (env.get('GRUB_CMDLINE_LINUX', ''), env.get('GRUB_CMDLINE_LINUX_DEFAULT', ''))
    env['GRUB_CMDLINE_LINUX_DEFAULT'] = ' '.join([env.get('GRUB_CMDLINE_LINUX_DEFAULT', '')] + _kernel_args(cmdline)).strip()
    env['GRUB_DISABLE_RECOVERY'] = 'true'
    try:
        done = subprocess.run([linux], capture_output=True, text=True, env=env, timeout=300)
        output = done.stdout if done.returncode == 0 else ''
    except (OSError, subprocess.SubprocessError):
        output = ''
    entry, kernel = make_entry(output, strings())
    if entry is None:
        problems.record('anticheat-entry', 'LOCAL109', repair=[['update-grub']])
        return 0
    problems.clear('anticheat-entry')
    place, detail = grub_place()
    if place == 'esp':
        sys.stdout.write(_esp_once_reader(detail))
    sys.stdout.write(entry)
    if place == 'none':
        say('LOCAL106', kernel, detail)
        return 0
    where = GRUBENV if place == 'grubenv' else ESP + ESP_BLOCK
    _atomic_write(ENTRY_FILE, 'ENTRY=%s\nPLACE=%s\nKERNEL=%s\n' % (
        ENTRY_ID, 'grubenv' if place == 'grubenv' else 'esp:%s:%s' % (detail, ESP_BLOCK), kernel))
    say('LOCAL105', kernel, where)
    return 0


def _esp_once_reader(fs_uuid=None):
    """Where GRUB cannot write /boot/grub, the one-time request is the edition's variable in the EFI system partition's
    block: read, cleared and acted on as Debian's 00_header does with next_entry."""
    if fs_uuid is None:
        return ''
    block = '(${sparky_anticheat_esp})' + ESP_BLOCK
    return '\n'.join([
        'set sparky_anticheat_esp=',
        'search --no-floppy --fs-uuid --set=sparky_anticheat_esp %s' % fs_uuid,
        'if [ -n "${sparky_anticheat_esp}" ]; then',
        '  set %s=' % ESP_VARIABLE,
        '  load_env -f "%s" %s' % (block, ESP_VARIABLE),
        '  if [ -n "${%s}" ]; then' % ESP_VARIABLE,
        '    set default="%s"' % ENTRY_ID,
        '    set %s=' % ESP_VARIABLE,
        '    save_env -f "%s" %s' % (block, ESP_VARIABLE),
        '    set boot_once=true',
        '  fi',
        'fi',
        '']) + '\n'


# ------------------------------------------------------------------ the one-time restart (root, through pkexec)
def _editenv(block, *words):
    return _run([os.environ.get('SPARKY_GRUB_EDITENV', 'grub-editenv'), block] + list(words), timeout=30)


def _listed(block):
    done = _editenv(block, 'list')
    if done.returncode:
        raise OSError(done.stderr.strip() or 'grub-editenv exit %d' % done.returncode)
    values = {}
    for line in done.stdout.splitlines():
        if '=' in line:
            key, value = line.split('=', 1)
            values[key] = value
    return values


def restart(command):
    """set, unset or status. Exit status: 0 done (status: available), 2 not root, 3 not available here, 4 failed."""
    state = _entry_state()
    available = (os.path.isdir(EFI) and state.get('ENTRY') == ENTRY_ID and state.get('PLACE', 'none') != 'none')
    if command == 'status':
        print('yes' if available else 'no')
        return 0 if available else 3
    if os.geteuid() != 0 and not ROOT:
        say('LOCAL120')
        return 2
    place = state.get('PLACE', 'none')
    if command == 'unset':
        try:
            if place == 'grubenv' and os.path.exists(GRUBENV):
                if _listed(GRUBENV).get('next_entry') == ENTRY_ID:
                    done = _editenv(GRUBENV, 'unset', 'next_entry')
                    if done.returncode:
                        raise OSError(done.stderr.strip())
            elif place.startswith('esp:'):
                block = ESP + place.split(':', 2)[2]
                if _listed(block).get(ESP_VARIABLE):
                    done = _editenv(block, 'unset', ESP_VARIABLE)
                    if done.returncode:
                        raise OSError(done.stderr.strip())
        except (OSError, subprocess.SubprocessError) as error:
            say('LOCAL122', str(error))
            return 4
        try:
            os.remove(ONCE_FILE)
        except OSError:
            pass
        say('LOCAL123')
        return 0
    if command != 'set':
        print('usage: anticheat-restart set|unset|status', file=sys.stderr)
        return 2
    if not available:
        say('LOCAL121', ENTRY_FILE)
        return 3
    cfg = _read(GRUB_CFG) or ''
    if "'%s'" % ENTRY_ID not in cfg:
        say('LOCAL121', GRUB_CFG)
        return 3
    try:
        if place == 'grubenv':
            # GRUB's own one-time choice (grub-reboot: next_entry, which Debian's 00_header takes once and clears)
            done = _run([os.environ.get('SPARKY_GRUB_REBOOT', 'grub-reboot'), ENTRY_ID], timeout=60)
            if done.returncode:
                raise OSError(done.stderr.strip() or 'grub-reboot exit %d' % done.returncode)
            if _listed(GRUBENV).get('next_entry') != ENTRY_ID:
                raise OSError('%s: next_entry was not written' % GRUBENV)
            where = GRUBENV
        else:
            where = ESP + place.split(':', 2)[2]
            done = _editenv(where, 'set', '%s=1' % ESP_VARIABLE)
            if done.returncode:
                raise OSError(done.stderr.strip() or 'grub-editenv exit %d' % done.returncode)
            if _listed(where).get(ESP_VARIABLE) != '1':
                raise OSError('%s: %s was not written' % (where, ESP_VARIABLE))
    except (OSError, subprocess.SubprocessError) as error:
        say('LOCAL122', str(error))
        return 4
    try:
        _atomic_write(ONCE_FILE, where + '\n')
    except OSError:
        pass
    say('LOCAL124', where)
    return 0


# ------------------------------------------------------------------ what Easy Anti-Cheat would see
def _pem_certificates(pem):
    return [base64.b64decode(''.join(block.split()))
            for block in re.findall(r'-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----', pem, re.S)]


def _subject(der):
    done = subprocess.run(['openssl', 'x509', '-inform', 'DER', '-noout', '-subject', '-issuer', '-nameopt',
                           'utf8,sep_comma_plus,sname'], input=der, capture_output=True, timeout=30)
    subject = issuer = ''
    for line in done.stdout.decode('utf-8', 'replace').splitlines():
        if line.startswith('subject='):
            subject = line[8:].strip()
        elif line.startswith('issuer='):
            issuer = line[7:].strip()
    return subject, issuer


def _common_name(subject):
    found = re.search(r'(?:^|,\s*)CN\s*=\s*([^,]+)', subject)
    return found.group(1).strip() if found else subject


def _fingerprint_file(path):
    data = _read(path, 'rb')
    if not data:
        return None
    if data.startswith(b'-----BEGIN'):
        certs = _pem_certificates(data.decode('ascii', 'replace'))
        data = certs[0] if certs else None
    return hashlib.sha256(data).hexdigest() if data else None


def pe_signatures(data):
    """The PKCS #7 signatures of a PE image (Microsoft PE/COFF: the certificate table, data directory 4, holds
    WIN_CERTIFICATE entries, each eight-byte aligned; type 2 is PKCS_SIGNED_DATA)."""
    if data[:2] != b'MZ' or len(data) < 0x40:
        return []
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    if data[pe:pe + 4] != b'PE\0\0':
        return []
    optional = pe + 24
    magic = struct.unpack_from('<H', data, optional)[0]
    directories = optional + (112 if magic == 0x20b else 96)
    offset, size = struct.unpack_from('<II', data, directories + 4 * 8)
    found = []
    position = offset
    while offset and position + 8 <= offset + size <= len(data):
        length, _revision, kind = struct.unpack_from('<IHH', data, position)
        if length < 8:
            break
        if kind == 2:
            found.append(data[position + 8:position + length])
        position += (length + 7) & ~7
    return found


def signer_certificates(pkcs7):
    done = subprocess.run(['openssl', 'pkcs7', '-inform', 'DER', '-print_certs'], input=pkcs7, capture_output=True,
                          timeout=30)
    return _pem_certificates(done.stdout.decode('ascii', 'replace'))


def _leaf(certs):
    """The signing certificate: the one that issued no other certificate in the set; (der, subject, issuer)."""
    named = [(der,) + _subject(der) for der in certs]
    issuers = {issuer for _der, subject, issuer in named if issuer != subject}
    for der, subject, issuer in named:
        if subject not in issuers:
            return der, subject, issuer
    return named[0] if named else (None, '', '')


def well_known(subject, issuer=''):
    return bool(WELL_KNOWN.search(subject or '') or WELL_KNOWN.search(issuer or ''))


def _valve_or_handheld():
    vendor = (_read(SYSFS + '/class/dmi/id/sys_vendor') or '').strip()
    chassis = (_read(SYSFS + '/class/dmi/id/chassis_type') or '').strip()
    # SMBIOS chassis types 30 to 32 (tablet, convertible, detachable) are how handhelds report themselves
    return vendor == 'Valve', vendor == 'Valve' or chassis in ('30', '31', '32')


def esl_certificates(data):
    """X.509 certificates of an EFI_SIGNATURE_LIST sequence (UEFI 2.10, 32.4.1), as in MokListRT."""
    found = []
    position = 0
    while data and position + 28 <= len(data):
        kind = data[position:position + 16]
        list_size, header_size, entry_size = struct.unpack_from('<III', data, position + 16)
        if list_size < 28 or entry_size < 16:
            break
        start = position + 28 + header_size
        if kind == X509_GUID:
            item = start
            while item + entry_size <= position + list_size:
                found.append(data[item + 16:item + entry_size])
                item += entry_size
        position += list_size
    return found


def event_log(data):
    """(number of events, the boot manager's own measurements present) of a TCG event log: the first event in the SHA-1
    form, then the crypto-agile form its Spec ID Event03 describes (TCG PC Client Platform Firmware Profile, 10.4)."""
    if len(data) < 32:
        return 0, False
    size = struct.unpack_from('<I', data, 28)[0]
    spec = data[32:32 + size]
    position = 32 + size
    sizes = {}
    agile = spec.startswith(b'Spec ID Event03')
    if agile and len(spec) >= 28:
        count = struct.unpack_from('<I', spec, 24)[0]
        for index in range(count):
            alg, digest = struct.unpack_from('<HH', spec, 28 + 4 * index)
            sizes[alg] = digest
    events, boot_manager = 1, False
    while position + 8 <= len(data):
        pcr, kind = struct.unpack_from('<II', data, position)
        position += 8
        if agile:
            count = struct.unpack_from('<I', data, position)[0]
            position += 4
            for _ in range(count):
                alg = struct.unpack_from('<H', data, position)[0]
                position += 2 + sizes.get(alg, TPM_ALG_DIGEST_SIZES.get(alg, 0))
        else:
            position += 20
        if position + 4 > len(data):
            break
        size = struct.unpack_from('<I', data, position)[0]
        position += 4 + size
        if position > len(data):
            break
        events += 1
        if pcr in BOOT_MANAGER_PCRS:
            boot_manager = True
    return events, boot_manager


def _module_signers():
    """Loaded modules from outside the kernel's tree (taint O) or without a signature (taint E): (name, signer, key)."""
    found = []
    base = SYSFS + '/module'
    try:
        names = sorted(os.listdir(base))
    except OSError:
        return None
    for name in names:
        taint = (_read(os.path.join(base, name, 'taint')) or '').strip()
        if 'O' not in taint and 'E' not in taint:
            continue
        signer = key = ''
        try:
            done = _run([_tool('modinfo'), '-F', 'signer', name], timeout=30)
            signer = done.stdout.strip()
            key = _run([_tool('modinfo'), '-F', 'sig_key', name], timeout=30).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            pass
        found.append((name, signer if 'E' not in taint else '', key.replace(':', '').upper()))
    return found


def _refused_names():
    """The modules this start's kernel refused (systemd-modules-load and udev: "Failed to insert module 'NAME': Key was
    rejected by service"; modprobe: "could not insert 'NAME': Key was rejected by service"), from this boot's journal."""
    try:
        done = _run([_tool('journalctl'), '-b', '-o', 'cat', '--no-pager', '-g', 'Key was rejected by service'], timeout=60)
    except (OSError, subprocess.SubprocessError):
        return []
    return sorted(set(re.findall(r"insert (?:module )?'([\w-]+)'", done.stdout)))


def _lockdown_refusals():
    try:
        done = _run([_tool('journalctl'), '-b', '-k', '-o', 'cat', '--no-pager', '-g', 'unsigned module loading is restricted'],
                    timeout=60)
    except (OSError, subprocess.SubprocessError):
        return 0
    return len(done.stdout.splitlines())


def _unverifiable_not_loaded():
    """Modules of this kernel's updates folder, not loaded, signed by this computer's DKMS key or not at all."""
    serial = _dkms_serial()
    base = os.path.join(ROOT + '/lib/modules', os.environ.get('SPARKY_STEREO_RELEASE', os.uname().release), 'updates')
    loaded = set(os.listdir(SYSFS + '/module')) if os.path.isdir(SYSFS + '/module') else set()
    found = []
    for folder, _dirs, files in os.walk(base):
        for name in sorted(files):
            if not re.search(r'\.ko(\.(xz|zst|gz))?$', name):
                continue
            module = re.sub(r'\.ko(\.(xz|zst|gz))?$', '', name)
            if module.replace('-', '_') in loaded:
                continue
            try:
                done = _run([_tool('modinfo'), '-F', 'sig_key', os.path.join(folder, name)], timeout=30)
            except (OSError, subprocess.SubprocessError):
                continue
            key = done.stdout.strip().replace(':', '').upper().lstrip('0')
            if done.returncode == 0 and (not key or (serial and key == serial)):
                found.append(module)
    return sorted(set(found))


def _unverified_loaded():
    """Loaded modules whose signature the kernel could not verify (taint E): lockdown refuses them."""
    found = []
    try:
        for name in os.listdir(SYSFS + '/module'):
            if 'E' in (_read(os.path.join(SYSFS, 'module', name, 'taint')) or ''):
                found.append(name)
    except OSError:
        pass
    return found


def _unsigned_installed():
    """Modules of the running kernel's updates folder (DKMS, the edition's prebuilt ones) that carry no signature."""
    base = os.path.join(ROOT + '/lib/modules', os.uname().release if not ROOT else os.environ.get('SPARKY_STEREO_RELEASE',
                                                                                                  os.uname().release), 'updates')
    found = []
    for folder, _dirs, files in os.walk(base):
        for name in sorted(files):
            if not re.search(r'\.ko(\.(xz|zst|gz))?$', name):
                continue
            try:
                done = _run([_tool('modinfo'), '-F', 'sig_id', os.path.join(folder, name)], timeout=30)
            except (OSError, subprocess.SubprocessError):
                continue
            if done.returncode == 0 and not done.stdout.strip():
                found.append(re.sub(r'\.ko(\.(xz|zst|gz))?$', '', name))
    return sorted(set(found))


def _dkms_serial():
    data = _read(DKMS_CERT, 'rb')
    if not data:
        return None
    form = 'PEM' if data.startswith(b'-----BEGIN') else 'DER'
    done = subprocess.run(['openssl', 'x509', '-inform', form, '-noout', '-serial'], input=data, capture_output=True,
                          timeout=30)
    serial = done.stdout.decode().strip().split('=', 1)[-1].upper()
    return serial.lstrip('0') or None


def check(as_root=None):
    """The rows: (id, state, text). state: met, not-met, unknown, info."""
    s = strings()
    rows = []
    as_root = os.geteuid() == 0 if as_root is None else as_root
    cmdline = _cmdline()
    anticheat = MARK in cmdline
    uefi = os.path.isdir(EFI)
    edition = _fingerprint_file(EDITION_CERT)
    dkms = _fingerprint_file(DKMS_CERT)

    rows.append(('start', 'info', text(s, 'LOCAL130' if anticheat else 'LOCAL131')))

    # 3. Secure Boot, with the firmware's keys
    secure = _efivar('SecureBoot', EFI_GLOBAL)
    setup = _efivar('SetupMode', EFI_GLOBAL)
    valve, handheld = _valve_or_handheld()
    if valve:
        rows.append(('secure-boot', 'not-met', text(s, 'LOCAL184')))
    elif not uefi:
        rows.append(('secure-boot', 'not-met', text(s, 'LOCAL135')))
    elif secure is None:
        rows.append(('secure-boot', 'not-met' if os.path.isdir(EFIVARS) else 'unknown',
                     text(s, 'LOCAL136' if os.path.isdir(EFIVARS) else 'LOCAL137')))
    elif secure[:1] == b'\x01':
        rows.append(('secure-boot', 'met', text(s, 'LOCAL132')))
    elif setup is not None and setup[:1] == b'\x01':
        rows.append(('secure-boot', 'not-met', text(s, 'LOCAL134')))
    else:
        rows.append(('secure-boot', 'not-met', text(s, 'LOCAL133')))

    # 1. the kernel, signed with a well-known key
    image = os.environ.get('SPARKY_STEREO_KERNEL_IMAGE', ROOT + '/boot/vmlinuz-' + os.uname().release)
    data = _read(image, 'rb')
    if data is None:
        rows.append(('kernel-key', 'unknown', text(s, 'LOCAL141', image)))
    else:
        signatures = pe_signatures(data)
        certs = [der for blob in signatures for der in signer_certificates(blob)]
        if not certs:
            rows.append(('kernel-key', 'not-met', text(s, 'LOCAL140', image)))
        elif edition and any(hashlib.sha256(der).hexdigest() == edition for der in certs):
            rows.append(('kernel-key', 'not-met', text(s, 'LOCAL138')))
        else:
            found = [_subject(der) for der in certs]
            known = [subject for subject, issuer in found if well_known(subject, issuer)]
            if known:
                rows.append(('kernel-key', 'met', text(s, 'LOCAL177', _common_name(known[0]))))
            else:
                _der, subject, _issuer = _leaf(certs)
                rows.append(('kernel-key', 'not-met', text(s, 'LOCAL178', _common_name(subject))))

    # every enrolled Machine Owner Key must be well-known too (Epic's FAQ)
    if uefi:
        mok = _efivar('MokListRT', SHIM_LOCK)
        if mok is None:
            rows.append(('mok', 'met', text(s, 'LOCAL142')))
        else:
            ours, others, known = [], [], []
            for der in esl_certificates(mok):
                digest = hashlib.sha256(der).hexdigest()
                subject, issuer = _subject(der)
                name = _common_name(subject)
                if digest in (edition, dkms):
                    ours.append(name)
                elif well_known(subject, issuer):
                    known.append(name)
                else:
                    others.append(name)
            if ours or others:
                rows.append(('mok', 'not-met', text(s, 'LOCAL143', ', '.join(ours + others))))
            elif known:
                rows.append(('mok', 'met', text(s, 'LOCAL179', ', '.join(known))))
            else:
                rows.append(('mok', 'met', text(s, 'LOCAL142')))

    # modules from outside the kernel, built and signed by an organization with a well-known key
    modules = _module_signers()
    if modules is None:
        rows.append(('modules', 'unknown', text(s, 'LOCAL149')))
    elif not modules:
        rows.append(('modules', 'met', text(s, 'LOCAL145')))
    else:
        serial = _dkms_serial()
        unsigned = [n for n, signer, _k in modules if not signer]
        here = [n for n, signer, key in modules if signer and serial and key.lstrip('0') == serial]
        other = [(n, signer) for n, signer, key in modules if signer and n not in here and not well_known(signer)]
        if unsigned:
            rows.append(('modules', 'not-met', text(s, 'LOCAL146', ', '.join(unsigned))))
        if here:
            rows.append(('modules', 'not-met', text(s, 'LOCAL147', ', '.join(here))))
        if other:
            rows.append(('modules', 'not-met', text(s, 'LOCAL148', ', '.join('%s (%s)' % pair for pair in other))))
        if not (unsigned or here or other):
            rows.append(('modules', 'met', text(s, 'LOCAL180', ', '.join(sorted({signer for _n, signer, _k in modules})))))
    tainted = (_read(PROC + '/sys/kernel/tainted') or '0').strip()
    if tainted.isdigit() and int(tainted) & TAINT_UNSIGNED_MODULE and not any(r[0] == 'modules' and r[1] == 'not-met' for r in rows):
        rows.append(('modules-loaded', 'not-met', text(s, 'LOCAL182')))

    # modules installed for this kernel outside its tree with no signature: lockdown refuses them (LOCKDOWN_MODULE_SIGNATURE
    # is below LOCKDOWN_INTEGRITY_MAX, include/linux/security.h), so in the anti-cheat start they do not load
    if anticheat:
        blocked = sorted(set(_refused_names() + _unsigned_installed()))
        if not blocked and _lockdown_refusals():
            # the kernel logs the refusal without the module's name ("Lockdown: modprobe: unsigned module loading is
            # restricted", security/lockdown/lockdown.c): name this kernel's modules it cannot verify that did not load
            blocked = _unverifiable_not_loaded()
    else:
        blocked = sorted(set(_unverified_loaded() + _unsigned_installed()))
    if blocked:
        rows.append(('modules-refused', 'not-met', text(s, 'LOCAL176' if anticheat else 'LOCAL175', ', '.join(blocked))))

    # 2. TPM 2.0
    major = (_read(SYSFS + '/class/tpm/tpm0/tpm_version_major') or '').strip()
    if major == '2':
        rows.append(('tpm', 'met', text(s, 'LOCAL150')))
    elif major:
        rows.append(('tpm', 'not-met', text(s, 'LOCAL151', major)))
    else:
        rows.append(('tpm', 'not-met', text(s, 'LOCAL152')))

    # 4. measured boot: the firmware's event log, with the boot manager's measurement
    log = SECURITYFS + '/tpm0/binary_bios_measurements'
    if not os.path.exists(log):
        rows.append(('measured-boot', 'not-met', text(s, 'LOCAL155')))
    else:
        content = _read(log, 'rb')
        if content is None:
            rows.append(('measured-boot', 'met', text(s, 'LOCAL154')))
        else:
            events, boot_manager = event_log(content)
            rows.append(('measured-boot', 'met' if boot_manager else 'not-met',
                         text(s, 'LOCAL153' if boot_manager else 'LOCAL156', events)))

    # 5. the IOMMU on, passthrough off
    try:
        units = sorted(os.listdir(SYSFS + '/class/iommu'))
    except OSError:
        units = []
    kinds = set()
    try:
        for group in os.listdir(SYSFS + '/kernel/iommu_groups'):
            kind = (_read(os.path.join(SYSFS, 'kernel/iommu_groups', group, 'type')) or '').strip()
            if kind:
                kinds.add(kind)
    except OSError:
        pass
    # a unit the firmware described is not yet an IOMMU in use: devices are behind it only when it has groups
    if (not units or not kinds) and handheld:
        rows.append(('iommu', 'met', text(s, 'LOCAL183')))
    elif not units or not kinds:
        rows.append(('iommu', 'not-met', text(s, 'LOCAL159')))
    elif 'identity' in kinds:
        rows.append(('iommu', 'not-met', text(s, 'LOCAL158')))
    else:
        rows.append(('iommu', 'met', text(s, 'LOCAL157', ', '.join(units))))

    # 6. lockdown in integrity mode (or stricter)
    lockdown = _read(SECURITYFS + '/lockdown')
    level = re.search(r'\[(\w+)\]', lockdown or '')
    if not level:
        rows.append(('lockdown', 'unknown', text(s, 'LOCAL162')))
    elif level.group(1) in ('integrity', 'confidentiality'):
        rows.append(('lockdown', 'met', text(s, 'LOCAL160', level.group(1))))
    else:
        rows.append(('lockdown', 'not-met', text(s, 'LOCAL161')))

    # 7. kexec disabled at boot time
    disabled = (_read(PROC + '/sys/kernel/kexec_load_disabled') or '').strip()
    at_boot = any(a in ('sysctl.kernel.kexec_load_disabled=1', 'sysctl.kernel/kexec_load_disabled=1') for a in cmdline)
    if disabled == '1' and at_boot:
        rows.append(('kexec', 'met', text(s, 'LOCAL163')))
    elif disabled == '1':
        rows.append(('kexec', 'unknown', text(s, 'LOCAL164')))
    elif disabled == '0':
        rows.append(('kexec', 'not-met', text(s, 'LOCAL165')))
    else:
        rows.append(('kexec', 'unknown', text(s, 'LOCAL166')))

    # 8. the BPF LSM loaded and active
    lsm = _read(SECURITYFS + '/lsm')
    if lsm is None:
        rows.append(('bpf-lsm', 'unknown', text(s, 'LOCAL169')))
    elif 'bpf' in lsm.strip().split(','):
        rows.append(('bpf-lsm', 'met', text(s, 'LOCAL167')))
    else:
        rows.append(('bpf-lsm', 'not-met', text(s, 'LOCAL168')))

    # hibernation in this start
    disk = _read(SYSFS + '/power/disk') or ''
    if '[disabled]' in disk:
        rows.append(('hibernation', 'info', text(s, 'LOCAL170')))

    # the anti-cheat start on this computer
    state = _entry_state()
    if not anticheat:
        if not uefi:
            rows.append(('entry', 'info', text(s, 'LOCAL107')))
        elif state.get('ENTRY') == ENTRY_ID:
            rows.append(('entry', 'info', text(s, 'LOCAL171')))
        else:
            rows.append(('entry', 'info', text(s, 'LOCAL172')))
    return rows


def report(as_json=False):
    rows = check()
    s = strings()
    if as_json:
        print(json.dumps({'source': 'Easy Anti-Cheat Linux v2, Epic Online Services, 2026-10-14',
                          'anticheatStart': MARK in _cmdline(),
                          'rows': [{'id': i, 'state': state, 'text': t} for i, state, t in rows]},
                         ensure_ascii=False, indent=1))
    else:
        print(text(s, 'LOCAL125'))
        words = {'met': text(s, 'LOCAL126'), 'not-met': text(s, 'LOCAL127'), 'unknown': text(s, 'LOCAL128'),
                 'info': text(s, 'LOCAL129')}
        for _i, state, line in rows:
            print('[%s] %s' % (words[state], line))
    return 1 if any(state in ('not-met', 'unknown') for _i, state, _t in rows) else 0


def anticheat_start():
    """At the anti-cheat start (sparky-stereo-boot-anticheat.service, only with sparky_stereo.anticheat=1): the session's
    notifier says that this start has no hibernation, as a notice of this boot (the engine's boot scope)."""
    if MARK not in _cmdline():
        return 0
    try:
        import sparky_stereo_problems as engine
        engine.keep('sparky-stereo-boot', 'anticheat-start', 'LOCAL173', [], scope=engine.BOOT, severity='notice')
    except Exception as error:  # the notice is said in the journal when the engine cannot keep it
        print('sparky-stereo-boot: %s (%s)' % (text(strings('en'), 'LOCAL173'), error), file=sys.stderr)
        return 1
    return 0


def resumed():
    """After a resume (sparky-stereo-boot-anticheat-resume.service, before grub2-common.service): GRUB may have written
    its environment block while this system was hibernated (the anti-cheat start took the one-time request, then its
    guard switched the computer off), and this system still holds the block as it was before. grub2-common.service
    rewrites the whole block from that copy (grub-editenv unset recordfail), which brought the one-time request back
    (measured in the virtual machine). The cached pages are clean, so dropping them makes the next read the disk's."""
    for path in (GRUBENV, ESP + ESP_BLOCK):
        try:
            fd = os.open(path, os.O_RDONLY)
        except OSError:
            continue
        try:
            os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_DONTNEED)
        finally:
            os.close(fd)
    return 0


def main(argv):
    command = argv[0] if argv else ''
    if command == 'grub':
        return grub_entry()
    if command in ('set', 'unset', 'status'):
        return restart(command)
    if command == 'check':
        return report('--json' in argv[1:])
    if command == 'start':
        return anticheat_start()
    if command == 'resumed':
        return resumed()
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
