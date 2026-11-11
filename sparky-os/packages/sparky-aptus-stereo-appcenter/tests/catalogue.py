#!/usr/bin/python3
"""The menu must retain every image/emulator/3D-role entry and use known packages."""
import json
from pathlib import Path
import sys
catalogue=Path(sys.argv[1])
lists=Path(sys.argv[2])
def lines(name):
    return [s.split('#')[0].strip() for s in (lists/name).read_text().splitlines() if s.split('#')[0].strip()]
rows=json.loads(catalogue.read_text())
known={s for name in ('image.list','apps.list','emulation-3d.list','gaming.list') for s in lines(name)}
known.update(s.split()[0] for s in lines('roles.tsv'))
known.add('vlc-stereo') # make-meta.py: OURS_PLAYER
# the VPN and Tools sections (ORDER 252c) are what the person may add from Debian: their packages are on no image list on
# purpose (the plain VPN plugins the image already carries are on system.list)
offered={row['package'] for row in rows if row['kind']=='apt' and row['section'] in ('vpn','tools')}
packages={row['package'] for row in rows if row['kind']=='apt'} - offered
assert packages <= known, packages-known
vpn=[row for row in rows if row['section']=='vpn']
assert vpn and all(row['package'].startswith('network-manager-') and 'gnome' not in row['package'] for row in vpn)
assert not {row.get('package') for row in rows}&{'network-manager-vpnc-gnome','network-manager-openvpn-gnome'}
onimage=set(lines('system.list'))
assert {'network-manager-openvpn','network-manager-openconnect','network-manager-l2tp'} <= onimage
assert {'network-manager-openvpn','network-manager-openconnect','network-manager-l2tp'} <= {row['package'] for row in vpn}
installed=set(lines('apps.list')+lines('image.list')+lines('system.list'))
# the VPN page names the plain plugins the image already carries; the Tools section is for what the image does not install
tools={name for row in rows if row['section']=='tools' for name in [row['package']]+row.get('also',[])}
assert not tools & installed, 'a Tools entry names no package the image installs: removing the entry would remove it'
assert not offered & set(lines('apps.list')+lines('image.list')), 'a program the image installs is not an extra'
assert 'network-manager-vpnc' not in {row.get('package') for row in rows}, 'network-manager-vpnc has left forky'
required=set(lines('image.list')+lines('emulation-3d.list'))
required.update(s.split()[0] for s in lines('roles.tsv') if s.split()[-1]=='3d')
assert required <= packages, required-packages
assert {row['package'] for row in rows if row['section']=='emulation'}==set(lines('emulation-3d.list'))
assert len({row['id'] for row in rows})==len(rows)
print(f'PASS {len(rows)} entries; required lists covered; no unknown package')
