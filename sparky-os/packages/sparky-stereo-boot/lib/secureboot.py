#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/25
"""The Sparky Stereo OS key on an installed system, for Secure Boot.

  secureboot.py esp    keep the edition's public certificate next to every shim on the EFI system partition
  secureboot.py grub   write the GRUB menu entry that enrolls it (run by /etc/grub.d/35_sparky_stereo_secureboot)

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
Environment: SPARKY_STEREO_ESP (default /boot/efi), SPARKY_STEREO_CERT (default the packaged certificate),
SPARKY_STEREO_LANG_DIR (default /usr/share/sparky/sparky-stereo-boot), LANG; from the grub.d script:
SPARKY_STEREO_KERNEL_PATH (the kernel as GRUB reaches it), SPARKY_STEREO_KERNEL_ACCESS (GRUB's lines to reach its
file system, grub-mkconfig_lib's prepare_grub_to_access_device) and SPARKY_STEREO_ESP_UUID (the partition's).
"""
import filecmp
import os
import shutil
import sys
import unicodedata

CERT_NAME = 'sparky-stereo-secureboot-2026.der'
CERT = os.environ.get('SPARKY_STEREO_CERT', '/usr/share/sparky-stereo-boot/secureboot/' + CERT_NAME)
ESP = os.environ.get('SPARKY_STEREO_ESP', '/boot/efi')
LANG_DIR = os.environ.get('SPARKY_STEREO_LANG_DIR', '/usr/share/sparky/sparky-stereo-boot')
LANGS = ['en', 'pl', 'pt_BR', 'fr', 'de', 'ja', 'ko', 'zh_CN', 'zh_TW']
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


def esp(quiet=False):
    """Copy the certificate next to every shim; returns the folders that hold it."""
    held = []
    if not os.path.isfile(CERT):
        return held
    for d in efi_dirs():
        target = os.path.join(d, CERT_NAME)
        try:
            if not (os.path.isfile(target) and filecmp.cmp(CERT, target, shallow=False)):
                shutil.copyfile(CERT, target)
                if not quiet:
                    print('sparky-stereo-boot: %s' % target)
            held.append(d)
        except OSError as e:   # a read-only or full partition never stops a package installation
            print('sparky-stereo-boot: cannot write %s: %s' % (target, e), file=sys.stderr)
    return held


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


def grub():
    held = esp(quiet=True)
    if not held:
        return   # no shim on an EFI system partition here (a BIOS boot, or another boot loader)
    # the system's own folder (os-release ID, as grub-install names it), else the first that is not EFI/BOOT;
    # the certificate is in each of them
    names = [os.path.basename(d) for d in held]
    folder = next((n for n in names if n.lower() == os_id()), None) or next((n for n in names if n.lower() != 'boot'), names[0])
    first = system_lang()
    order = [first] + [lang for lang in LANGS if lang != first]
    own = strings(first)
    title = own.get('LOCAL12') or strings('en').get('LOCAL12', 'Secure Boot: enroll the Sparky Stereo OS key')
    out = ['if [ "$grub_platform" = efi ]; then',
           '    if [ "$grub_cpu" = x86_64 ]; then',
           "        menuentry '%s' --id sparky-enroll {" % title.replace("'", '')]
    for lang in order:
        s = strings(lang)
        text = s.get('LOCAL13')
        if not text:
            continue
        for line in wrap('%s: %s' % (s.get('LOCAL14', lang), text.replace('{folder}', folder))):
            out.append('            echo "%s"' % line.replace('"', '').replace('$', '').replace('\\', ''))
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
    out += ['            sleep --interruptible --verbose 60'] + find + [
            '            terminal_output console',
            '            chainloader ($sparky_mm)%s' % mm,
            '        }']
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
        esp()
    elif cmd == 'grub':
        grub()
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
