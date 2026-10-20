#!/usr/bin/python3
# Tests of sparky-stereo-boot's export, each in a fake root (sysfs, /etc, /var/lib, /boot):
# KWin's saved settings in, the files the boot reads out, compared with what each case must give.
# Run as root in a container with grub-common (grub-editenv), python3:
#   run-tests.py PATH/TO/sparky-stereo-boot
import json, os, pwd, shutil, subprocess, sys, tempfile

TOOL = os.path.abspath(sys.argv[1])
HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, 'fixtures')
EDIDS = {n: open(os.path.join(FIX, n + '.edid'), 'rb').read() for n in ('qemu-stereo', 'ex725', 'hx855')}
IDS = {'qemu-stereo': ('RHT 4660 0 42 2014 0', '770cfb3061eeadb072cbab0b9587b258'),
       'ex725': ('SNY 11266 16843009 1 2011 0', 'e39ea3a74d0e07ce7ccfe457505689a6'),
       'hx855': ('SNY 29698 16843009 1 2012 0', '6afef7a1b57efabe8b1f0d6c6d869993')}
results = []


def output(edid, connector, mode, uuid, **extra):
    ident, md5 = IDS[edid]
    o = {'connectorName': connector, 'edidIdentifier': ident, 'edidHash': md5, 'uuid': uuid,
         'mode': {'width': mode[0], 'height': mode[1], 'refreshRate': mode[2], 'flags': mode[3]}}
    o.update(extra)
    return o


def config(outputs, setups):
    return json.dumps([{'name': 'outputs', 'data': outputs}, {'name': 'setups', 'data': setups}]).encode()


def setup(*entries):
    return {'lidClosed': False, 'outputs': [{'enabled': e, 'outputIndex': i, 'position': {'x': 0, 'y': 0}, 'priority': p}
                                            for i, p, e in entries]}


def run_case(name, screens, data, options='', expect_kernel=None, expect_gfxmode=None, expect_main_layout=None,
             expect_greeters=None, expect_sddm=None, sddm_dm=False):
    root = tempfile.mkdtemp(prefix='ssb-')
    try:
        for card, connector, edid in screens:
            d = os.path.join(root, 'sys/class/drm', '%s-%s' % (card, connector))
            os.makedirs(d)
            open(os.path.join(d, 'status'), 'w').write('connected\n')
            open(os.path.join(d, 'edid'), 'wb').write(EDIDS[edid] if edid else b'')
        os.makedirs(os.path.join(root, 'sys/class/drm/card0-DP-9'))
        open(os.path.join(root, 'sys/class/drm/card0-DP-9/status'), 'w').write('disconnected\n')
        os.makedirs(os.path.join(root, 'boot/grub'))
        subprocess.run(['grub-editenv', os.path.join(root, 'boot/grub/grubenv'), 'create'], check=True)
        os.makedirs(os.path.join(root, 'etc/default'))
        open(os.path.join(root, 'etc/default/sparky-stereo-boot'), 'w').write(options)
        for account in ('plasmalogin', 'sddm'):
            try:
                os.makedirs(root + pwd.getpwnam(account).pw_dir)
            except KeyError:
                pass
        if sddm_dm:
            os.makedirs(os.path.join(root, 'etc/systemd/system'))
            os.symlink('/lib/systemd/system/sddm.service', os.path.join(root, 'etc/systemd/system/display-manager.service'))
        cfg = os.path.join(root, 'input.json')
        open(cfg, 'wb').write(data)
        env = dict(os.environ, SPARKY_STEREO_ROOT=root, SPARKY_STEREO_NO_UPDATE_GRUB='1')
        p = subprocess.run([TOOL, 'export-file', cfg, 'tester'], env=env, capture_output=True, text=True)
        if p.returncode != 0:
            report(name, False, 'exit %d: %s' % (p.returncode, p.stderr.strip()[-300:]))
            return
        record = json.load(open(os.path.join(root, 'var/lib/sparky-stereo-boot/main-output.json')))
        env_list = subprocess.run(['grub-editenv', os.path.join(root, 'boot/grub/grubenv'), 'list'],
                                  capture_output=True, text=True).stdout
        grub_vars = open(os.path.join(root, 'var/lib/sparky-stereo-boot/grub.cfg')).read()
        problems = []
        kernel = ' '.join(record['kernelArguments'])
        if expect_kernel is not None and kernel != expect_kernel:
            problems.append('kernel %r, expected %r' % (kernel, expect_kernel))
        env_value = next((l.split('=', 1)[1] for l in env_list.splitlines() if l.startswith('sparky_stereo_boot=')), '')
        if env_value != kernel:
            problems.append('grubenv %r differs from the record %r' % (env_value, kernel))
        gfx = next((l.split('=', 1)[1] for l in grub_vars.splitlines() if l.startswith('SPARKY_STEREO_GFXMODE=')), '')
        if expect_gfxmode is not None and gfx != expect_gfxmode:
            problems.append('gfxmode %r, expected %r' % (gfx, expect_gfxmode))
        layout = (record['main'] or {}).get('layout')
        if expect_main_layout is not None and layout != expect_main_layout:
            problems.append('layout %r, expected %r' % (layout, expect_main_layout))
        if expect_greeters is not None:
            if record['greeters'] != expect_greeters:
                problems.append('greeters %r, expected %r' % (record['greeters'], expect_greeters))
            for account in expect_greeters:
                path = root + pwd.getpwnam(account).pw_dir + '/.config/kwinoutputconfig.json'
                st = os.stat(path)
                if open(path, 'rb').read() != data:
                    problems.append('%s copy differs from the input' % account)
        if expect_sddm is not None and os.path.exists(os.path.join(root, 'etc/sddm.conf.d/50-sparky-stereo-boot.conf')) != expect_sddm:
            problems.append('SDDM Wayland file present: %s, expected %s' % (not expect_sddm, expect_sddm))
        report(name, not problems, '; '.join(problems) or 'kernel: %s | gfxmode: %s | layout: %s' % (kernel or '-', gfx or '-', layout))
    finally:
        shutil.rmtree(root)


def report(name, ok, detail):
    results.append(ok)
    print('%-44s %s  %s' % (name, 'PASS' if ok else 'FAIL', detail))


Q = ('card0', 'Virtual-1', 'qemu-stereo')
vm_real = open(os.path.join(FIX, 'vm-real-kwinoutputconfig.json'), 'rb').read()
run_case('real VM file, 2D 1280x800 (not preferred)', [Q], vm_real,
         expect_kernel='video=Virtual-1:1280x800@75', expect_gfxmode='1280x800', expect_main_layout='2d')
run_case('real VM file + EX725 on HDMI-A-1: main TV', [Q, ('card0', 'HDMI-A-1', 'ex725')], vm_real,
         expect_kernel='', expect_gfxmode='1920x1080', expect_main_layout='2d')

one = lambda flags, mode=(1920, 1080, 60000), **kw: config([output('qemu-stereo', 'Virtual-1', mode + (flags,), 'u1', **kw)], [setup((0, 1, True))])
run_case('frame packing 1080p60', [Q], one(0x80),
         expect_kernel='plymouth.stereo=Virtual-1:frame-packing:mode=1920x1080@60000 video=Virtual-1:1920x1080@60',
         expect_gfxmode='1920x1080', expect_main_layout='frame-packing')
run_case('frame packing 24p', [Q], one(0x80, (1920, 1080, 24000)),
         expect_kernel='plymouth.stereo=Virtual-1:frame-packing:mode=1920x1080@24000 video=Virtual-1:1920x1080@24')
run_case('side by side full, swap eyes', [Q], one(0x100, stereoSwapEyes=True),
         expect_kernel='plymouth.stereo=Virtual-1:sbs-full:mode=1920x1080@60000:swap video=Virtual-1:1920x1080@60')
run_case('top and bottom at the preferred rate', [Q], one(0x40, (1920, 1080, 74998)),
         expect_kernel='plymouth.stereo=Virtual-1:tab:mode=1920x1080@74998')
run_case('anaglyph modern (virtual twin)', [Q], one(0x20200, (1920, 1080, 74998)),
         expect_kernel='plymouth.stereo=Virtual-1:anaglyph-modern:mode=1920x1080@74998', expect_main_layout='anaglyph-modern')
run_case('anaglyph CRT', [Q], one(0x20400, (1920, 1080, 74998)),
         expect_kernel='plymouth.stereo=Virtual-1:anaglyph-crt:mode=1920x1080@74998')
run_case('side by side half by hand', [Q], one(0x20020, (1920, 1080, 74998)),
         expect_kernel='plymouth.stereo=Virtual-1:sbs-half-2d:mode=1920x1080@74998')
run_case('top and bottom by hand', [Q], one(0x20040, (1920, 1080, 74998)),
         expect_kernel='plymouth.stereo=Virtual-1:tab-2d:mode=1920x1080@74998')
run_case('rows, right eye first', [Q], one(0x21000, (1920, 1080, 74998)),
         expect_kernel='plymouth.stereo=Virtual-1:rows:mode=1920x1080@74998:swap')
run_case('rows, right first + swap eyes = left first', [Q], one(0x21000, (1920, 1080, 74998), stereoSwapEyes=True),
         expect_kernel='plymouth.stereo=Virtual-1:rows:mode=1920x1080@74998')
run_case('columns, left first', [Q], one(0x22000, (1920, 1080, 74998)),
         expect_kernel='plymouth.stereo=Virtual-1:columns:mode=1920x1080@74998')
run_case('checkerboard, right first', [Q], one(0x30000, (1920, 1080, 74998)),
         expect_kernel='plymouth.stereo=Virtual-1:checkerboard:mode=1920x1080@74998:swap')
run_case('frame-sequential, left first', [Q], one(0x60000, (1920, 1080, 74998)),
         expect_kernel='plymouth.stereo=Virtual-1:sequential:mode=1920x1080@74998')
run_case('splash in 2D (3D from the login screen)', [Q], one(0x80), options='SPARKY_STEREO_SPLASH=2d\n',
         expect_kernel='video=Virtual-1:1920x1080@60', expect_gfxmode='1920x1080')
run_case('boot does not follow (SPARKY_STEREO_BOOT=no)', [Q], one(0x80), options='SPARKY_STEREO_BOOT=no\n',
         expect_kernel='', expect_gfxmode='')
run_case('GRUB left to the firmware', [Q], one(0x80), options='SPARKY_STEREO_GRUB=auto\n', expect_gfxmode='')
run_case('another screen than the saved one', [('card0', 'Virtual-1', 'hx855')], one(0x80),
         expect_kernel='', expect_gfxmode='', expect_main_layout=None)

two = [('card0', 'HDMI-A-1', 'ex725'), ('card0', 'HDMI-A-2', 'hx855')]
pair_cfg = lambda mode, a_extra, b_extra, b_conn='HDMI-A-2': config(
    [output('ex725', 'HDMI-A-1', (1920, 1080, 60000, 0x1), 'ua', stereoPairMode=mode, stereoPartner='ub', **a_extra),
     output('hx855', b_conn, (1920, 1080, 60000, 0x1), 'ub', stereoPairMode=mode, stereoPartner='ua', **b_extra)],
    [setup((0, 1, True), (1, 2, True))])
run_case('pair: dual projection', two, pair_cfg('DualProjection', {'stereoPairRole': 'Left'}, {'stereoPairRole': 'Right'}),
         expect_kernel='plymouth.stereo=HDMI-A-1:left:mode=1920x1080@60000,HDMI-A-2:right:mode=1920x1080@60000',
         expect_main_layout='pair-DualProjection')
run_case('pair: mirror rig, right panel reflected', two,
         pair_cfg('MirrorRig', {'stereoPairRole': 'Left', 'stereoPairReflection': 'None'},
                  {'stereoPairRole': 'Right', 'stereoPairReflection': 'Horizontal'}),
         expect_kernel='plymouth.stereo=HDMI-A-1:left:mode=1920x1080@60000,HDMI-A-2:right:mode=1920x1080@60000:hflip')
run_case('pair: iZ3D, formula 3, encoded', two,
         pair_cfg('Ized3d', {'stereoPairRole': 'Back', 'ized3dMode': 3, 'ized3dTransfer': 1},
                  {'stereoPairRole': 'Front', 'ized3dMode': 3, 'ized3dTransfer': 1}),
         expect_kernel='plymouth.stereo=HDMI-A-1:iz3d-back:mode=1920x1080@60000:formula=3:encoded,'
                       'HDMI-A-2:iz3d-front:mode=1920x1080@60000:formula=3:encoded')
run_case('pair on two GPUs, both HDMI-A-1: card= named', [('card0', 'HDMI-A-1', 'ex725'), ('card1', 'HDMI-A-1', 'hx855')],
         pair_cfg('DualProjection', {'stereoPairRole': 'Left'}, {'stereoPairRole': 'Right'}, b_conn='HDMI-A-1'),
         expect_kernel='plymouth.stereo=HDMI-A-1:left:mode=1920x1080@60000:card=card0,HDMI-A-1:right:mode=1920x1080@60000:card=card1')
two_screens = config([output('ex725', 'HDMI-A-1', (1920, 1080, 60000, 0x80), 'ua'),
                      output('hx855', 'HDMI-A-2', (1920, 1080, 60000, 0x1), 'ub')],
                     [setup((0, 2, True), (1, 1, True))])
run_case('two screens: the main one (priority 1) is 2D', [('card0', 'HDMI-A-1', 'ex725'), ('card0', 'HDMI-A-2', 'hx855')],
         two_screens, expect_kernel='', expect_main_layout='2d')
twins = config([output('ex725', 'HDMI-A-1', (1920, 1080, 60000, 0x1), 'ua'),
                output('ex725', 'HDMI-A-2', (1920, 1080, 60000, 0x80), 'ub')],
               [setup((0, 2, True), (1, 1, True))])
run_case('the same TV model twice: told apart by connector', [('card0', 'HDMI-A-1', 'ex725'), ('card0', 'HDMI-A-2', 'ex725')],
         twins, expect_kernel='plymouth.stereo=HDMI-A-2:frame-packing:mode=1920x1080@60000', expect_main_layout='frame-packing')
have_accounts = all(a for a in ('plasmalogin', 'sddm') if a)
try:
    pwd.getpwnam('plasmalogin'); pwd.getpwnam('sddm')
    run_case('login screens get the settings', [Q], one(0x80), expect_greeters=['plasmalogin', 'sddm'])
    run_case('login screens: SPARKY_STEREO_GREETER=no', [Q], one(0x80), options='SPARKY_STEREO_GREETER=no\n', expect_greeters=[])
    run_case('SDDM in 3D: Wayland greeter file written', [Q], one(0x80), expect_sddm=True, sddm_dm=True)
    run_case('SDDM in 2D: no Wayland greeter file', [Q], one(0x1, (1920, 1080, 74998)), expect_sddm=False, sddm_dm=True)
    run_case('Plasma Login Manager: no SDDM file', [Q], one(0x80), expect_sddm=False, sddm_dm=False)
except KeyError:
    print('(no plasmalogin and sddm accounts: login screen cases skipped)')
def refused(name, data):
    root = tempfile.mkdtemp(prefix='ssb-')
    try:
        env = dict(os.environ, SPARKY_STEREO_ROOT=root, SPARKY_STEREO_NO_UPDATE_GRUB='1')
        cfg = os.path.join(root, 'input.json')
        open(cfg, 'wb').write(data)
        p = subprocess.run([TOOL, 'export-file', cfg, 'tester'], env=env, capture_output=True, text=True)
        written = os.path.exists(os.path.join(root, 'var/lib/sparky-stereo-boot/main-output.json'))
        report(name, p.returncode == 1 and not written, 'exit %d, record written: %s, %s' % (p.returncode, written, p.stderr.strip()[-80:]))
    finally:
        shutil.rmtree(root)
refused('refuses what is not KWin settings', b'{"x": 1}')
refused('refuses broken JSON', b'[{"name": "outputs", ')
print('SUMMARY %d of %d pass' % (sum(results), len(results)))
sys.exit(0 if all(results) else 1)
