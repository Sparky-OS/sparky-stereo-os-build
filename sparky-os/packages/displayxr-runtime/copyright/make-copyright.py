#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Assemble debian/copyright for the DisplayXR runtime package (ORDER 58).

Usage: make-copyright.py WORKDIR OUT MIT_CMU_TEXT
MIT_CMU_TEXT is the MIT-CMU licence text of libstereo-declare (LICENSES/MIT-CMU.txt of Sparky-OS/libstereo-declare),
whose protocol XML patch 0003 adds. WORKDIR holds reuse-lint.json (the v2.66.3 tree), dep-mcp-lint.json and dep-common-lint.json (the two
FetchContent components), holders-*.txt, the unpacked trees (t/displayxr-runtime-2.66.3, dep-mcp,
dep-common) and stereo-xml.txt (the copyright block of kde-stereo-content-v1.xml, which a patch adds).
Every file's own SPDX tags decide its paragraph (tools/reuse2dep5.py); what REUSE does not know is written
here by hand, each with the file it was read from. E-mail addresses are left out of the holder lines."""
import pathlib
import re
import subprocess
import sys

W = pathlib.Path(sys.argv[1])
OUT = pathlib.Path(sys.argv[2])
MIT_CMU = pathlib.Path(sys.argv[3])
HERE = pathlib.Path(__file__).resolve().parent
TREE = W / 't/displayxr-runtime-2.66.3'
EMAIL = re.compile(r'\s*<[^<>@\s]+@[^<>\s]+>')


def gen(lint, prefix, lic, holders, exclude=()):
    import json
    data = json.loads((W / lint).read_text())
    data['files'] = [f for f in data['files'] if prefix + f['path'] not in exclude]
    filtered = W / ('filtered-' + lint)
    filtered.write_text(json.dumps(data))
    out = subprocess.run([sys.executable, '-I', str(HERE / 'reuse2dep5.py'), str(filtered), prefix, lic,
                          str(W / holders)], check=True, capture_output=True, text=True)
    names = out.stderr.split('LICENSES:', 1)[1].split()
    return EMAIL.sub('', out.stdout), set(names)


def wayland_holders():
    holders = []
    for f in sorted((TREE / 'src/external/wayland-protocols').glob('*.xml')):
        block = re.search(r'<copyright>(.*?)</copyright>', f.read_text(), re.S).group(1)
        for line in block.splitlines():
            m = re.match(r'\s*Copyright\s*(?:©|\(c\))?\s*(.*\S)', line)
            if m:
                h = re.sub(r'\s+', ' ', EMAIL.sub('', m.group(1)).rstrip('.').replace(' © ', ' '))
                if h not in holders:
                    holders.append(h)
    return sorted(holders)


wl_files = sorted('src/external/wayland-protocols/' + f.name for f in (TREE / 'src/external/wayland-protocols').glob('*.xml'))
main, used = gen('reuse-lint.json', '', 'BSL-1.0', 'holders-main.txt', set(wl_files) | {'DCO'})
mcp, u = gen('dep-mcp-lint.json', 'displayxr-mcp/', 'Apache-2.0', 'holders-dxr.txt',
             {'displayxr-mcp/external/cjson/cJSON.c', 'displayxr-mcp/external/cjson/cJSON.h'})
used |= u
common, u = gen('dep-common-lint.json', 'displayxr-common/', 'Apache-2.0', 'holders-dxr.txt',
                {'displayxr-common/common/stb_image.h', 'displayxr-common/common/stb_image_write.h'})
used |= u

text = f"""Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: DisplayXR Runtime
Upstream-Contact: https://github.com/DisplayXR/displayxr-runtime/issues
Source: https://github.com/DisplayXR/displayxr-runtime (tag v2.66.3, c96f08b7ca5b57418123da0741a4a7bd6346a402)
 https://github.com/DisplayXR/displayxr-mcp (tag v0.5.6, e10a722ad20b59d667044833758c51faf7c253e8)
 https://github.com/DisplayXR/displayxr-common (tag v1.2.0, 917adf4719acc4f6787a5978b24f5f0c20f9994e)
 https://github.com/DisplayXR/displayxr-runtime/releases/tag/v2.66.3 (displayxr-runtime_2.66.3_amd64.deb)
Comment: DisplayXR is a fork of Monado (https://monado.freedesktop.org/) by
 Collabora, Ltd. and the Monado contributors (NOTICE). The paragraphs below
 follow each file's own SPDX-License-Identifier and SPDX-FileCopyrightText
 tags, read with reuse 6.2.0 (`reuse lint --json`) on each source tree, and
 .reuse/dep5 of the runtime for the files it covers; a file that names no
 licence is under the project's LICENSE (BSL-1.0 for the runtime, Apache-2.0
 for displayxr-mcp and displayxr-common, whose LICENSE and NOTICE say so).
 A folder is written FOLDER/* when every file in it has the same licence.
 The holders' e-mail addresses are in the files themselves and not repeated
 here.

{main}Files: src/external/wayland-protocols/*.xml
Copyright: {chr(10).join('           ' + h if i else h for i, h in enumerate(wayland_holders()))}
License: MIT-Wayland
Comment: Copied from wayland-protocols (src/external/wayland-protocols/README.md);
 the licence is the copyright block of each file.

Files: src/external/wayland-protocols/kde-stereo-content-v1.xml
Copyright: 2026 Daniel Campos Ramos
License: MIT-CMU
Comment: Added by debian/patches/0003-vk-native-declare-wayland.patch, byte for
 byte the protocol of libstereo-declare (https://github.com/Sparky-OS/libstereo-declare).

Files: DCO
Copyright: 2004, 2006 The Linux Foundation and its contributors
License: LicenseRef-DCO

{mcp}Files: displayxr-mcp/external/cjson/*
Copyright: 2009-2017 Dave Gamble and cJSON contributors
License: MIT

{common}Files: displayxr-common/common/stb_image.h
 displayxr-common/common/stb_image_write.h
Copyright: 2017 Sean Barrett
License: MIT or Unlicense

Files: release/*
Copyright: 2024-2026 The DisplayXR Project contributors
 2018-2025 Collabora, Ltd. and the Monado contributors
License: BSL-1.0
Comment: DisplayXR's own release package of v2.66.3, carried unchanged; its
 SHA-256, 7d216f4557d4eb54d5563a748c9f144218c79ab4a2ea48fd36fc5a216e7e8aaa,
 is the digest the GitHub release lists for it. Only its displayxr-dashboard
 is installed, in the displayxr-dashboard package. That program is a
 self-contained .NET single-file bundle; its manifest
 (displayxr-dashboard.deps.json) names these components, each with the
 licence of its NuGet package:
 .
  - the dashboard itself (src/dashboard of the runtime): BSL-1.0, The DisplayXR Project;
  - the .NET runtime 10.0.14 (Microsoft.NETCore.App.Runtime.linux-x64): MIT, Microsoft Corporation and the .NET Foundation;
  - Avalonia 11.2.3 and its Desktop, FreeDesktop, Native, Remote.Protocol, Skia, Themes.Fluent, Win32 and X11 parts: MIT, The AvaloniaUI Project;
  - Avalonia.Fonts.Inter 11.2.3: MIT, The AvaloniaUI Project; the Inter typeface it carries: OFL-1.1, 2016 The Inter Project Authors (https://github.com/rsms/inter);
  - SkiaSharp 2.88.9 and HarfBuzzSharp 7.3.0.3 with their Linux native libraries: MIT, Microsoft Corporation; the Skia and HarfBuzz code inside those libraries keeps the licences SkiaSharp's own third-party notices list;
  - MicroCom.Runtime 0.11.0: MIT, 2021 Nikita Tsukanov;
  - Tmds.DBus.Protocol 0.21.3: MIT, Tom Deseyn.
"""


def license_text(name):
    common = {'Apache-2.0', 'BSL-1.0', 'CC0-1.0', 'CC-BY-4.0', 'OFL-1.1'}
    if name in common:
        return f' On Debian systems the full text of this licence is in\n /usr/share/common-licenses/{name}.'
    files = {
        'MIT-CMU': MIT_CMU,
    }
    if name in files:
        body = files[name].read_text()
    elif name == 'MIT-Wayland':
        block = re.search(r'<copyright>(.*?)</copyright>', (TREE / 'src/external/wayland-protocols/viewporter.xml').read_text(), re.S).group(1)
        body = block.split('Permission is hereby granted', 1)[1]
        body = 'Permission is hereby granted' + body
    elif name == 'LicenseRef-DCO':
        body = ('Everyone is permitted to copy and distribute verbatim copies of this\n'
                'license document, but changing it is not allowed.\n')
    else:
        body = (TREE / 'LICENSES' / f'{name}.txt').read_text()
        if name == 'BSD-3-Clause':
            body = body.split('\n', 2)[2] if body.startswith('Copyright (c) <year>') else body
    lines = []
    for line in body.strip('\n').splitlines():
        line = line.strip()
        lines.append(' ' + line if line else ' .')
    return '\n'.join(lines)


names = sorted((used | {'MIT', 'MIT-Wayland', 'MIT-CMU', 'LicenseRef-DCO', 'Unlicense', 'BSL-1.0'}) - {''})
for n in names:
    text += f'\nLicense: {n}\n{license_text(n)}\n'
# the packaging's own paragraph comes last, in the shape the edition's provenance step writes, which keeps
# its BSL-1.0 (Sparky-OS/displayxr-packaging is under the Boost Software License 1.0, like DisplayXR)
text += """
Files: debian/*
Comment: Sparky Stereo OS packaging. Sparky Stereo OS, Daniel Ramos's edition of SparkyLinux (by Paweł "pavroo" Pijanowski).
 Under the Boost Software License 1.0 like DisplayXR (https://github.com/Sparky-OS/displayxr-packaging).
Copyright: 2026 Daniel Ramos (Capitain Jack)
License: BSL-1.0
"""
OUT.write_text(text)
print(f'{OUT}: {text.count(chr(10) + "Files: ") + 1} Files paragraphs, licences: {" ".join(names)}')
