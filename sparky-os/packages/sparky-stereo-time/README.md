Sparky Stereo Time
Sets chrony's time sources from the timezone: the country's official service, with NTS where it offers it, or its country's pool.ntp.org zone where the country has none.

Copyright (C) 2026 Paweł Pijanowski, Daniel Ramos (Capitain Jack) and others, see copyright file.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

Dependencies:
-------------
ca-certificates, chrony, python3, iproute2, systemd, sparky-stereo-problems, ucf

Notes:
-------------
Policy (Daniel, 2026-10-02): "drop the pool, keep the working letters in order starting with gps (my prefered server). Time authenticated, where no nts is present, is accepted since it's from the official server".
Official servers are used alone, with NTS where the service offers it and plain NTP otherwise.
Brazil uses gps.ntp.br first, followed by the working NTP.br letters in order.
No Debian pool is added beside a country's official servers, even when there is only one server.
Where no official service is listed, the country's pool.ntp.org zone is used, for example pt.pool.ntp.org for Portugal.
The pool catalogue lists country pools with servers in the pool operator's regional directories and resolving addresses, checked on 2026-11-02.
If neither an official service nor a usable country pool is listed, configuration and --check print a notice and succeed without keeping a problem.
The clock keeps Debian’s pool as Debian configures it; returning from a supported country restores the unedited Debian template through ucf and removes the generated edition sources.
An older LOCAL54 problem is cleared.
A timezone that cannot be placed in a country remains a fault, reported and kept until repaired.

Debian manages chrony.conf with ucf.
The tool removes Debian's pool from a copy of Debian's packaged template and gives that template to ucf.
An edited or deleted chrony.conf is preserved and reported through sparky-stereo-problems; no new time-source choice is applied over it.
A package trigger reapplies the policy after Debian updates its template.
Removing this package restores the unedited Debian configuration through ucf; personal edits are kept.
Two or more NTS servers retain authselectmode prefer; plain official services retain chrony's default authentication selection.

Nothing fails silently (Daniel, 2026-11-01: "either it works or not and the user must know"). What fails is said in the system's language and kept in `/var/lib/sparky-stereo-problems` with its evidence until it works again, and the session shows each kept problem once as a notification:
- a catalogue (`ntp-countries.tsv`) or timezone tables that cannot be read, or a timezone that is not known: nothing is written, and the sources in use stay as they were (exit 3). Debian's pool is never put in place of a country's servers because something failed;
- sources that cannot be written (exit 4);
- a running chrony that refuses the reload or the restart, or a failed chrony (exit 4); a chrony that is not running reads the sources when it starts, and that is said;
- none of the chosen servers answering: `sparky-stereo-time --check`, run by `sparky-stereo-time-check.timer` five minutes after the start and then every hour, reads chrony's reachability register (`chronyc -N -c sources`) and says what the clock follows instead. Without a network, or within three minutes of chrony's start or of a change of the sources, nothing is judged;
- a timezone watcher that cannot listen, and units that do not start after an installation.

`sparky-stereo-time --status` lists the kept problems, `sudo sparky-stereo-time --repair` runs again what each one names, and `sudo sparky-stereo-time --dismiss STEP` stops showing one until it changes or is repaired.

At boot `sparky-stereo-time.service` runs before chrony.service and writes the sources and the conf.d snippet, so chrony's first start already reads the right ones (the installer sets the timezone before the first boot). In a running session `sparky-stereo-time-watch.service` listens to timedated's PropertiesChanged signal on the system bus (KDE's settings and timedatectl go through it) and runs the tool, which reloads chrony's sources, or restarts chrony when the snippet changed. A path unit on /etc/localtime was dropped: it never fires, because the symlink is replaced by rename. A zone changed by hand with `ln -sf` is picked up at the next boot or by running `sparky-stereo-time`. The units are enabled by vendor symlinks, so `systemctl disable` does not apply. `/etc/chrony/conf.d/sparky-stereo.conf` (nocerttimecheck 1) is a conffile.

Build:
-------------
./build.sh   (the package lands in $SPARKY_REPO_DIR, or in $OUT)

Use:
-------------
sparky-stereo-time --print --zone America/Sao_Paulo
sudo sparky-stereo-time        (writes /etc/chrony/sources.d/sparky-stereo.sources)
sparky-stereo-time --status    (the kept problems)
sudo sparky-stereo-time --check

Test:
-------------
test/run-tests.sh   (as root in a throwaway debian:testing container, with the package and chrony installed)
