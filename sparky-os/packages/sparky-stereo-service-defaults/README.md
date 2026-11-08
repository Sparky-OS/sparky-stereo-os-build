sparky-stereo-service-defaults
Working defaults for services that fail at every boot on a fresh Sparky Stereo OS.

Copyright (C) 2026 Paweł Pijanowski, Daniel Ramos (Capitain Jack) and others, see copyright file.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

Each file is a systemd drop-in for one service of another package. A service is never removed or masked: it is configured so it works, and what it needs is supplied. Each drop-in says why, and each cause is reported to the package that owns it.

Nothing fails silently (Daniel, 2026-11-01: "either it works or not and the user must know"). Each drop-in empties `OnFailure=` and names `sparky-stereo-service-problem@.service`: a service that still cannot start is said in the system's language and kept by the edition's one engine, sparky-stereo-problems (`/var/lib/sparky-stereo-problems`), with its result, its exit status and its own last lines, until it starts again. The engine's session notifier shows each kept problem. A `/dev/null` link named `50-sparky-stereo-problems.conf` beside each drop-in masks the engine's top-level drop-in for that unit (including every xfs_healer instance), so each failure is told once, with what this package knows of it. Emptying `OnFailure=` alone does not remove that handler. Other units retain the engine's generic handler.

- `sparky-stereo-service-defaults status` lists the kept problems.
- `sudo sparky-stereo-service-defaults repair` starts each kept unit again.
- `sudo sparky-stereo-service-defaults dismiss UNIT` stops showing one until it changes or is repaired.

| Service | What failed at every boot | The working default |
| --- | --- | --- |
| snmptt | Its default `ipv6_enable = 1` needs Net::IP, which Debian's snmptt does not depend on | The edition's snmptt 1.5-3+sparky1 depends on libnet-ip-perl |
| pkcs11-daemon | Its default library, SoftHSM's, is not installed with it | The edition's pkcs11-daemon 0.4.1-5+sparky1 depends on libsofthsm2 |
| xfs_healer@- | On a root that is not XFS, `xfs_healer --supported` ended with status 255 | xfsprogs 7.2.0-1+sparky1 carries upstream's fde1eee: status 1, a skip |
| ipwatchd | Started before any interface has an IPv4 address | Waits for one (a skip); NetworkManager starts it; a failed probe is said |
| urfkill | Debian's 0.5.0-8 asks ConsoleKit for sessions (its debian/rules lost `--with-session-tracking=systemd`, Debian bug #1152866) | The edition's urfkill 0.5.0-8+sparky1 asks systemd-logind; this package Breaks Debian's; where Debian's is held in place anyway, its failure is said with the reason |
| clamav-freshclam-once | Enabled beside the freshclam daemon by clamav up to 1.4.4+dfsg-1, it cannot lock the shared log file (Debian bug #1134489) | Once, when 0.1.5 arrives: the once service and its timer are switched off where the daemon is on, and it is said; either can be switched on again |
| stas-config@ | /etc/nvme missing without nvme-cli | Created first |

Dependencies:
-------------
systemd, python3, iproute2

Build:
-------------
OUT=/path/to/output ./build.sh (inside debian:testing)
