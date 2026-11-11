# Microsoft core fonts downloaded on the installed machine

Rebuild Debian's msttcorefonts 3.8.1 with Michael Vogt's Ubuntu EULA presentation and default-false consent check adapted to its synchronous installer.
The Microsoft font files are never part of the package or the ISO.
The package declares its 3,934,864 byte CAB download through the shared ORDER 399 fields.

Run `build.sh` with `OUT` set to an empty output directory.
It downloads the pinned plain Debian source, checks its SHA-256, applies the credited changes, and builds a plain source and binary for review and testing in a container.
The edition's publication pipeline must qualify these authored sources through Lean Code before publication.
No published Lean Code source is imported into this recipe.

The Calamares and text installer integration invokes apt interactively on the target system, using this package's debconf question without an acceptance preseed.
Refusal prints that the fonts were not installed and gives the reconfigure command.
The synchronous downloader's integrity checks and failure exit remain Debian's.
An already accepted EULA is retained on upgrade; reconfiguration after refusal asks again.

Credits: Eric Sharkey and Thijs Kinkhorst for Debian msttcorefonts; Michael Vogt for Ubuntu's EULA presentation (Ubuntu bug 670629); Microsoft Corporation for the EULA and font software; Daniel Ramos (Capitain Jack) for the edition integration.
