sparky-stereo-housekeeping
BleachBit's presets and cleaners that the edition adds: Daniel's safe presets, and the "System mail" cleaner.

Copyright (C) 2026 Paweł Pijanowski, Daniel Ramos (Capitain Jack) and others, see copyright file.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

Presets
-------

Daniel, 2026-10-14: "my default settings apply for root and for the user - safe non removing languages"; ORDER, 2026-10-23, item b: ship them as the edition default, "shipped ready".
BleachBit reads one file, `~/.config/bleachbit/bleachbit.ini` (`bleachbit.options_file`, from `$HOME`); it has no system-wide default.
So the user's preset is `/etc/skel/.config/bleachbit/bleachbit.ini` (a conffile: every account tool copies it for a new person), and root's is copied to `/root/.config/bleachbit/bleachbit.ini` by the first install, only when root has no file.
A file that exists is never written, an upgrade writes nothing, and root's file is not written again after root deleted it.
An existing person has no file made for them: copy `/etc/skel/.config/bleachbit/bleachbit.ini` yourself if you want it.
Both presets are Daniel's A10 files without their `[list/shred_drives]` (BleachBit's free-space wipe targets, one personal path each; no free-space wipe is ticked) and `[hashpath]`.
Root's: apt (clean, autoclean, package lists), deepscan (ds_store, thumbs_db, tmp, vim swap), journald, system (cache, memory, rotated logs, tmp), x11 debug logs.
The user's: evolution cache, firefox (backup, cache, crash reports, vacuum), thunderbird (cache, vacuum), journald, system (cache, rotated logs, tmp).
Never `system.localizations`, never `apt.autoremove`, and none of the `system_mail` options.

System mail
-----------

Daniel, 2026-11-05: "that cleaning was due long ago - we should include those as a bleech bit option...(clear internal mailing system)".
Machine-generated mail (cron, anacron, netdata, sudo, chkrootkit, mail program bounces) is system logs.
A person's own mail is not, so the options say plainly what they delete.
None of them is ticked unless the person ticks it.

| Option | What it does | Who |
| --- | --- | --- |
| `system_mail.mailbox` | Empties `/var/mail/$USER` in place. Debian Policy 11.6 makes the mail spool 2775 root:mail, so a person can empty a mailbox but cannot delete it; the file keeps its owner and mode. | the person, or root |
| `system_mail.mailboxes` | Empties every mailbox in `/var/mail` (not the `.lock` files) and `/root/mbox`. | root |
| `system_mail.dead_letter` | Deletes `~/dead.letter` (root's, when root runs it). | the person, or root |
| `system_mail.queues` | Deletes the files in the queue of a mail program that is no longer installed: exim4 (`/var/spool/exim4`), postfix (its queue folders under `/var/spool/postfix`, not its chroot), nullmailer (`/var/spool/nullmailer/{queue,failed,tmp}`), dma (`/var/spool/dma`), msmtp (`~/.msmtp.queue`). ssmtp sends at once and has no queue. | root (the person, for msmtp) |

Run `bleachbit --preview system_mail.mailbox` first: it lists the files and their sizes and changes nothing.
A file it cannot clear (permission denied) is named in BleachBit's output, never skipped silently.
BleachBit does not take the mailbox lock that Debian Policy 11.6 asks mail programs to take: do not clear a mailbox while a message is being delivered to it.

The queue option and BleachBit
------------------------------

CleanerML has no condition on a package, so the option cannot say "only when the package is gone".
`/usr/lib/sparky-stereo-housekeeping/system_mail.py` writes `/usr/share/bleachbit/cleaners/system_mail.xml` from `system_mail.xml.in`, listing a queue only when `dpkg-query` says every package of its mail program is not-installed or config-files and the program (`/usr/sbin/exim4`, `/usr/sbin/postfix`, `/usr/sbin/nullmailer-send`, `/usr/sbin/dma`, `/usr/bin/msmtp`) is not on the system.
dpkg runs it again (a trigger) whenever one of those programs is installed or removed, and when bleachbit is installed or upgraded.
If it cannot write the cleaner, the engine (sparky-stereo-problems) says and keeps why; `sudo sparky-stereo-housekeeping repair` tries again.

Translations
------------

BleachBit translates a cleaner's text with its own catalog (the gettext domain `bleachbit`, owned by Debian's bleachbit package).
This package diverts each of the eight catalogs of the edition's languages (`de fr ja ko pl pt_BR zh_CN zh_TW`; English is the source) to `bleachbit.mo.debian` and writes in its place Debian's catalog with this package's strings added.
Debian's translation of a string always wins.
Removing the package gives Debian's catalogs back.
The strings are in `po/`; the same ones go to BleachBit with the cleaner, so the project's own translators carry them (`msgcat` then has nothing left to add).

Dependencies:
-------------
python3, gettext, dpkg, sparky-stereo-problems; bleachbit is recommended.

Build:
-------------
OUT=/path/to/output ./build.sh (inside debian:testing)
The tests (test/run-tests.sh) run the sealed package in a throwaway container with the published engine installed.
