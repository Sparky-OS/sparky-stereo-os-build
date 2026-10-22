#!/usr/bin/env python3
"""Prepare isolated boot/DKMS validation tools under the shared build-slot limit."""
from pathlib import Path
import json,subprocess,sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'sparky-os' / 'config'))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'sparky-os' / 'release'))
import local_config as cfg
from build_slots import start_build
base=cfg.path('SPARKY_MIGRATION_WORK');out=base/'kernel-validation-tools';out.mkdir(exist_ok=False)
name='sparky-lc-kernel-tools-prepare';tag='sparky-lc-kernel-checks:20261020'
recipe='''set -e
export DEBIAN_FRONTEND=noninteractive
apt-get -y update
apt-get -y --no-install-recommends install qemu-system-x86 ovmf swtpm swtpm-tools tpm2-tools libtss2-tcti-swtpm0 libtss2-tcti-device0 python3-virt-firmware sbsigntool efitools openssl busybox-static cpio kmod gzip xz-utils zstd ca-certificates procps file build-essential bc bison flex libssl-dev libelf-dev dwarves dkms
rm -rf /var/lib/apt/lists/*
'''
command=['docker','run','--name',name,'--cpus','4','sparky-lc-migration:20261020','bash','-c',recipe]
with (out/'build.log').open('w') as log:
 p=start_build(command,name,log);rc=p.wait()
if rc:raise SystemExit(f'Tool container failed with {rc}; retained for investigation')
image=subprocess.check_output(['docker','commit',name,tag],text=True).strip()
subprocess.run(['docker','rm',name],check=True)
(out/'status.json').write_text(json.dumps({'image':tag,'image_id':image,'passed':True,'scope':'isolated validation tools only; no kernel results'},indent=2)+'\n')
print(image)
