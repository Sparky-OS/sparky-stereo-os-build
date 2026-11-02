# command-not-found: the commands Debian installs under another name

Debian's command-not-found 23.04.0-3, rebuilt as 23.04.0-3+sparky1+lc1 with one change: a command that Debian installs under another name names that package first, with the name to run, and the packages that have the command under its own name stay listed after it (ORDER 252b, study row J15).

Debian Policy 10.1: "Two different packages must not install programs with different functionality but with the same filenames ... If this case happens, one of the programs must be renamed."
So sharkdp's `fd` is fd-find's `/usr/bin/fdfind`, because fdclone has `/usr/bin/fd`, and `bat` is bat's `/usr/bin/batcat`, because bacula-console-qt has `/usr/sbin/bat`.
command-not-found reads only the Contents index, so Debian's build offers fdclone for `fd` and bacula-console-qt for `bat`.

```
$ fd
Command 'fd' not found, but can be installed with:
sudo apt install fd-find  # run it as 'fdfind'
sudo apt install fdclone
```

A command with no row is advised exactly as Debian's build advises it.
A row whose package the database does not have is not offered.
When the renamed program is installed already, the message says so ("Command 'fd' is installed as '/usr/bin/fdfind' from deb fd-find") and lists the literal matches after it.

## Every caller

bash (`command_not_found_handle` in Debian's `/etc/bash.bashrc`), zsh (`/etc/zsh_command_not_found`, sourced by sparky-stereo-console's zshrc) and fish (its own handler) print command-not-found's message, so they need nothing else.
KRunner's missing program runner and Dolphin's packs (sparky-stereo-integration 0.1.2) read the same table: when the first package command-not-found names is the renamed one, KRunner offers each package it names, in its order, and Dolphin offers to install the renamed one; otherwise they offer one package, or none, as before.

## The table

`renamed-commands` is made by `make-renamed.py` from Debian's own data: forky's Contents and Packages indexes, Debian's popularity contest (`by_inst`), and each candidate source's `debian/README.Debian`, `debian/NEWS` and `debian/changelog` from sources.debian.org.
The script's header gives the three rules; each row's comment names the Debian text it rests on.
A rename where the program that keeps the name is the more installed one is left out, so its message stays as Debian's build writes it, and listed in the report.

Made on 2026-11-03 from forky's indexes of 2026-11-02 (573 candidates, 320 sources read):

| Command | Package | Installed as | Debian's words |
|---|---|---|---|
| `antlr` | antlr | `runantlr` | changelog: "Renamed /usr/bin/antlr to /usr/bin/runantlr because it conflicts with pccts. Closes: #127898" |
| `bat` | bat | `batcat` | README.Debian: "the executable and its manpage have been renamed from 'bat' to 'batcat' because of a file name clash with another Debian package" |
| `cl` | iraf | `irafcl` | README.Debian: "cl/ecl had to be renamed to "irafcl"" (cl-launch has `cl`) |
| `fd` | fd-find | `fdfind` | README.Debian: "Because /usr/bin/fd is already used by fdclone, we are install fd into /usr/lib/cargo/bin/fd and creating a symlink from this file to /usr/bin/fdfind." |

Left out, the program under the name being the more installed one (popularity contest installations): `cal` (ccal 262, ncal 32,443), `spline` (spline's `aspline` 13, plotutils 314), `ts` (task-spooler's `tsp` 182, moreutils 11,341), `wipe` (lam-runtime's `lamwipe` 206, wipe 1,948), `xsd` (xsdcxx 40, mono-devel 2,976).

To make it again:

```sh
# Debian's indexes, decompressed into DATA: Contents-<component>-<arch>.txt (the lines under bin and sbin),
# Packages-<component>-amd64, popcon-by_inst.gz (https://popcon.debian.org/by_inst.gz)
python3 -I make-renamed.py --data DATA --evidence EVIDENCE --fetch --out renamed-commands --report report.tsv
```

## Build

`build.sh WORK PREVIOUS_DIR SOURCE_DIR` runs `build-in-container.sh` in the Lean Code migration container: Debian's source package (checked by the hash of its `.dsc`), `patches/sparky-renamed-commands.patch` and a patch made from `renamed-commands` after Debian's series, the changelog entry from `changelog-sparky1.txt`, then the Lean Code source and the build with Debian's own tests (`python3 -m unittest discover`, which includes `test_renamed_commands.py` and pyflakes) and the link and start gate against Debian's 23.04.0-3 build.
It needs `SPARKY_REPO_DIR` (the published tree) and `SPARKY_LC_ARCHIVE_DIR` (sparky-os/lean/archive.md).

## Tests

`tests/test-callers.sh CANDIDATES OUT IMAGE` installs today's packages in a fresh Debian testing container (Debian's command-not-found, the published sparky-stereo-integration and sparky-stereo-console), probes `fd`, `bat` and five commands without a renamed package in bash, zsh, fish, KRunner's D-Bus Match and a Dolphin pack, installs the candidates and probes again; `tests/check-callers.py` judges red, green and unchanged, the message in the nine languages, and 300 sampled commands and 23 words that must be unchanged.

## Credits

command-not-found is Zygmunt Krynicki's program (2005 to 2008), developed in Ubuntu by Michael Vogt and maintained in Debian by Julian Andres Klode (Debian's copyright file).
Ubuntu's `priority.txt` (Michael Vogt, 2009, LP: #318442) ordered packages that have the command itself; it left with the sqlite database in 2018.
The renamed names are Debian's maintainers' decisions, quoted per row in the table.
