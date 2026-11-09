#!/usr/bin/python3 -I
# mkcase.py CASE OUTDIR: writes OUTDIR/root, the ext2 tree of one GRUB case: boot/grub (grub.cfg, grubenv, fonts), the kernel,
# an initrd and the artwork. The grub.cfg is fixture-grub.cfg, a generated one (00_header with the edition's fragment,
# 05_debian_theme, 06_sparky_theme, the first entry); a case changes one thing in the tree or in the cfg.
import os, shutil, sys

case, out = sys.argv[1], sys.argv[2]
UUID = '82cc1979-cdf1-40c9-b04b-bcedc6f6a866'
OTHER = '11111111-2222-3333-4444-555555555555'
KERNEL = '7.3.1-stereo3d16'
src = open('/work/fixture-grub.cfg').read()
head = src[src.index('### BEGIN /etc/grub.d/00_header ###'):src.index('menuentry \'Sparky Stereo OS GNU/Linux\'')]
entry = src[src.index('menuentry \'Sparky Stereo OS GNU/Linux\''):]
root = os.path.join(out, 'root')
for d in ('boot/grub/fonts', 'opt/artwork', 'usr/share/grub'):
    os.makedirs(os.path.join(root, d))

def put(path, data):
    p = os.path.join(root, path)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'wb').write(data if isinstance(data, bytes) else data.encode())

def copy(path, dst):
    p = os.path.join(root, dst)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    shutil.copy(path, p)

def block(text):
    return (text + '#' * (1024 - len(text))).encode()

copy('/usr/share/grub/unicode.pf2', 'usr/share/grub/unicode.pf2')
copy('/usr/share/grub/unicode.pf2', 'boot/grub/fonts/unicode.pf2')
copy('/work/art.png', 'opt/artwork/sparky-black.png')
copy('/work/kernel', 'boot/vmlinuz-' + KERNEL)
put('boot/initrd.img-' + KERNEL, b'not an initrd\n' * 100)
env = block('# GRUB Environment Block\nnext_entry=\n')

if case == 'good':
    pass
elif case == 'background-missing':      # 00_header, 05 and 06 name a picture a package took away after update-grub
    os.unlink(os.path.join(root, 'opt/artwork/sparky-black.png'))
elif case == 'background-cut':          # a PNG cut short by an interrupted copy
    put('opt/artwork/sparky-black.png', open('/work/art.png', 'rb').read()[:3000])
elif case == 'background-not-png':
    put('opt/artwork/sparky-black.png', b'<html>not a picture</html>')
elif case == 'root-uuid-changed':       # the root's UUID in grub.cfg no longer exists (disk cloned, partition made again)
    head, entry = head.replace(UUID, OTHER), entry.replace(UUID, OTHER)
elif case == 'font-missing':            # the menu font GRUB_FONT names (sparky-NN.pf2) removed after update-grub
    head = head.replace('if [ x$feature_default_font_path = xy ] ; then\n   font=unicode\nelse', 'if false ; then\n   font=unicode\nelse')
    head = head.replace('font="/usr/share/grub/unicode.pf2"', 'font="/boot/grub/fonts/sparky-30.pf2"')
elif case == 'kernel-missing':          # a purge removed the kernel the first entry names before update-grub wrote the menu again
    os.unlink(os.path.join(root, 'boot/vmlinuz-' + KERNEL))
elif case == 'initrd-missing':
    os.unlink(os.path.join(root, 'boot/initrd.img-' + KERNEL))
elif case == 'grubenv-damaged':         # the environment block overwritten
    env = b'garbage that is not an environment block\n'
elif case == 'edition-variable':        # sparky-stereo-boot's kernel line variable, as it writes it for a laptop panel
    env = block('# GRUB Environment Block\nsparky_stereo_boot=plymouth.stereo=eDP-1:anaglyph-modern:mode=1366x768@60 video=eDP-1:1366x768@60\n')
    entry = entry.replace('ro  quiet splash', 'ro  quiet splash ${sparky_stereo_boot}')
elif case == 'gfxmode-list':            # the edition's list for a 1366x768 panel, ending in auto
    head = head.replace('set gfxmode=1920x1080x32', 'set gfxmode=1366x768,1920x1080,1280x720,1024x768,auto')
elif case == 'saved-entry-gone':        # GRUB_DEFAULT=saved with a saved entry for a kernel that was purged
    head = head.replace('set default="0"', 'set default="${saved_entry}"')
    env = block('# GRUB Environment Block\nsaved_entry=gnulinux-7.3.1-stereo3d14-advanced-%s\n' % UUID)
elif case == 'default-out-of-range':
    head = head.replace('set default="0"', 'set default="7"')
elif case == 'next-entry-gone':         # grub-reboot to an entry that is gone
    env = block('# GRUB Environment Block\nnext_entry=gnulinux-7.3.1-stereo3d14-advanced-%s\n' % UUID)
else:
    raise SystemExit('unknown case ' + case)

# the test reads GRUB's messages from the serial port, beside the screen
head = head.replace('terminal_output gfxterm', 'terminal_output serial gfxterm')
cfg = 'serial --unit=0 --speed=115200\nterminal_input serial console\nterminal_output serial\n' + head + entry
put('boot/grub/grub.cfg', cfg)
put('boot/grub/grubenv', env)
