#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
import subprocess,sys
from pathlib import Path
stage=Path(sys.argv[1]);files=[]
for name in ('qaption','libcaptiond-client-dev','libcaptiond-client-tests-dev','libcaptiond-client0','captiond','kaption-common','kaption','sparky-stereo-partners','sparky-stereo-live-captions'):
    found=list(stage.glob(name+'_*.deb'));assert len(found)==1,(name,found);files.append(str(found[0]))
subprocess.run(['dpkg','-i']+files,check=True)
subprocess.run(['apt-get','check'],check=True)
