# SPDX-License-Identifier: GPL-2.0-or-later
import configparser
from pathlib import Path
import sys
show = configparser.ConfigParser()
show.read('plasma/stereoshowrc')
assert show['General'].getboolean('Enabled')
assert show['General'].getint('IdleSeconds') == 8100
assert show['General'].getint('CycleSeconds') == 600
power = configparser.ConfigParser()
power.read(Path(sys.argv[1]) / 'powerdevilrc')
assert power['AC][Display'].getint('DimDisplayIdleTimeoutSec') == 900
assert power['AC][Display'].getint('TurnOffDisplayIdleTimeoutSec') == 9900
assert power['AC][Display'].getboolean('LockBeforeTurnOffDisplay')
assert power['Battery][Display'].getint('TurnOffDisplayIdleTimeoutSec') == 1200
assert power['AC][SuspendAndShutdown'].getint('AutoSuspendIdleTimeoutSec') == 14400
assert 9900 - show['General'].getint('IdleSeconds') == 1800
locker = configparser.ConfigParser()
locker.read(Path(sys.argv[1]) / 'kscreenlockerrc')
assert not locker['Daemon'].getboolean('Autolock')
assert locker['Daemon'].getint('LockGrace') == 0
print('PASS: edition power config + show config provide the decided 30-minute AC window; PowerDevil owns locking/off/suspend')
