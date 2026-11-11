#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/11
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/11
"""Run only inside a disposable container; all file operations use fixtures."""
from pathlib import Path
import runpy
import stat
import sys
import tempfile

reconcile = runpy.run_path(sys.argv[1])['reconcile']
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    fstab, mask = root / 'fstab', root / 'tmp.mount'
    esp = b'UUID=ABCD-1234 /boot/efi vfat defaults,umask=0077 0 2\n'
    tmp = b'tmpfs\t/tmp\ttmpfs\tdefaults,noatime,mode=1777 0 0\n'
    others = b'# tmpfs /tmp tmpfs defaults 0 0\nUUID=data /tmp ext4 defaults 0 2\ntmpfs /run/test tmpfs defaults 0 0\n'
    original = esp + tmp + others
    fstab.write_bytes(original)
    fstab.chmod(0o640)
    assert not reconcile(fstab, mask)
    assert fstab.read_bytes() == original
    mask.write_text('[Mount]\nWhat=tmpfs\n')
    assert not reconcile(fstab, mask)
    assert fstab.read_bytes() == original
    mask.unlink()
    mask.symlink_to('/dev/null')
    assert reconcile(fstab, mask)
    expected = esp + b'# Disabled by sparky-stereo-kernel-settings: tmp.mount is masked.\n# ' + tmp + others
    assert fstab.read_bytes() == expected
    assert stat.S_IMODE(fstab.stat().st_mode) == 0o640
    backup = root / 'fstab.before-sparky-tmp-on-disk'
    assert backup.read_bytes() == original
    assert stat.S_IMODE(backup.stat().st_mode) == 0o640
    assert not reconcile(fstab, mask)
    assert fstab.read_bytes() == expected
    fstab.write_bytes(tmp)
    assert reconcile(fstab, mask)
    assert backup.read_bytes() == original
print('PASS: masked tmpfs entry reconciled; ESP, other mounts, comments, permissions, backup, unmasked/admin unit and repeat runs preserved')
