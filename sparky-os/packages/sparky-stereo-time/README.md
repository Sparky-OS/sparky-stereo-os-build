Sparky Stereo Time
Sets chrony's time sources from the timezone: the country's official service, with NTS where it offers it, or Debian's pool where the country has none.

Copyright (C) 2026 Paweł Pijanowski, Daniel Ramos (Capitain Jack) and others, see copyright file.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

Dependencies:
-------------
ca-certificates, chrony

Notes:
-------------
Policy (Daniel): time authenticated wherever the country's official service offers NTS; where it does not, its plain NTP servers are accepted because they come from the official server. chrony.conf is never touched (Debian manages it with ucf). The Debian pool stays configured; chrony's own source selection keeps it out of the way.
- Two or more NTS servers (BR, DE, AT, SE): a generated `/etc/chrony/conf.d/sparky-stereo-auth.conf` with `authselectmode prefer`: once any source is authenticated, unauthenticated ones, the pool included, are never selected. If every NTS server is unreachable there is no fallback.
- One NTS server (DK, ES, FR): the default `mix` and `pool debian.pool.ntp.org iburst maxsources 2`, unless the row also lists a plain official server, which then replaces the Debian pool.
- Plain official servers only (CH, GB, PL, BE, AR, CO, RU, MY and, with one server, TR, FI, NO, ID, ZA): plain `server` lines and no authselectmode line; a single server gets the Debian pool beside it.
- No service: `pool debian.pool.ntp.org iburst`.
The data file keeps the order of the servers.

At boot `sparky-stereo-time.service` runs before chrony.service and writes the sources and the conf.d snippet, so chrony's first start already reads the right ones (the installer sets the timezone before the first boot). In a running session `sparky-stereo-time-watch.service` listens to timedated's PropertiesChanged signal on the system bus (KDE's settings and timedatectl go through it) and runs the tool, which reloads chrony's sources, or restarts chrony when the snippet changed. A path unit on /etc/localtime was dropped: it never fires, because the symlink is replaced by rename. A zone changed by hand with `ln -sf` is picked up at the next boot or by running `sparky-stereo-time`. The units are enabled by vendor symlinks, so `systemctl disable` does not apply. `/etc/chrony/conf.d/sparky-stereo.conf` (nocerttimecheck 1) is a conffile.

Build:
-------------
./build.sh   (the package lands in /K3D/temp/sparky-os/repo, or in $OUT)

Use:
-------------
sparky-stereo-time --print --zone America/Sao_Paulo
sudo sparky-stereo-time        (writes /etc/chrony/sources.d/sparky-stereo.sources)

Test:
-------------
test/run-tests.sh   (in a debian:testing container, with chrony installed)
