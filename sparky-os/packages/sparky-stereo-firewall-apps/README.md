KDE Connect through the firewall, from the local network

When the person turns the firewall (ufw) on, KDE Connect's ufw application profile (`/etc/ufw/applications.d/kdeconnect`, ports 1714:1764 tcp and udp) is allowed once from the private and link-local network ranges, as ordinary rules that System Settings, Firewall lists and can delete.
The firewall itself stays off by default, as Debian ships it.
The profiles are listed in `/usr/share/sparky-stereo-firewall-apps/local-network-apps`.
A rule that could not be added is kept by sparky-stereo-problems; `sudo sparky-stereo-firewall-apps` tries again.

Copyright (C) 2026 Paweł Pijanowski, Daniel Ramos (Capitain Jack), see copyright file.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

Dependencies:
-------------
sparky-stereo-problems (>= 0.1.2)

Install:
-------------
Install the package with apt; a dpkg trigger on /etc/ufw/applications.d does the rest.
