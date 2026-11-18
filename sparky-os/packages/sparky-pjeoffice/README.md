sparky-pjeoffice
The installer and the KDE integration of CNJ's PJeOffice Pro, the signer of Brazil's court e-filing system (PJe).

Copyright (C) 2026 Daniel Ramos (Capitain Jack), see copyright file.

This program is free software: you can redistribute it and/or modify it
under the GNU General Public License, version 3 or any later version.

What it does:
-------------
- Nothing of CNJ's is in this package. The official ZIP is fetched from CNJ's own address when the package is installed (the control file declares the size and the address, so apt and Stereo APTus say them first, and warn on a metered connection), checked against the size and SHA-256 written in catalogue/catalogue.json by a reviewer, unpacked into /opt/pjeoffice-pro/versions/VERSION, qualified (the files are there, the jar is whole, the bundled Java runs as the reviewed one), and only then switched in: /opt/pjeoffice-pro/current is a link renamed over the old one.
- The previous version stays in its folder. `sparky-pjeoffice rollback` goes back to it.
- CNJ's own updater is switched off in the installed copy (pjeoffice-update.properties, update.url=disabled; the original is kept as .cnj beside it). A new version reaches the person as a new version of this package, after it was reviewed.
- The bundled Java 8 stays: it is the only one measured to sign (Java 21's certificate reader rejects the program's certificates; see the skill brazil-certificates).
- The program reads its own list of certificates for secure connections (pjeoffice.jks, inside its jar) and never the system's. The list made here keeps every original entry byte for byte and adds the system's, and is made again when /etc/ssl/certs changes (a dpkg trigger). A running signer uses the new list after it is restarted; the tray says so.
- /usr/bin/pjeoffice-pro starts the program from a resolved version folder with its logs kept (the last three starts); the private codec libraries of sparky-pjeoffice-codec are put on the library path of that process only.
- A menu entry, the tray entry (/etc/xdg/autostart, started at login unless the person turns it off on the System Settings page), the page itself, and a Dolphin action for PDFs that makes a CAdES file beside the PDF with the program's own supported entry point. The program's window asks for the certificate and the PIN; this package never sees them.
- Every failure is kept by sparky-stereo-problems with what to do; Repair runs the installation again.

Command:
-------------
sparky-pjeoffice install | remove | rollback | trust [--if-changed] | status [--json] | check | sign-pdf FILE... | launch [--tell]

Test:
-------------
tests/installer.sh in a disposable container (generated stand-ins for CNJ's ZIP, a local HTTPS server); tests/catalogue-matches-control.py; the tests of the watcher in watcher/.

Install:
-------------
Stereo APTus, Office, Documents, or: su; apt-get install sparky-pjeoffice

Uninstall:
-------------
su; apt-get remove sparky-pjeoffice   (the person's certificates, settings and files stay)
