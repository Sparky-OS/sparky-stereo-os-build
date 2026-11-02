# command-not-found: the commands Debian installs under another name

Debian's command-not-found 23.04.0-3, rebuilt as 23.04.0-3+sparky1+lc1 with one change: a command that Debian installs under another name names that package too, with the name to run, and the packages that have the command under its own name stay listed (ORDER 252b, study row J15).

Debian Policy 10.1: "Two different packages must not install programs with different functionality but with the same filenames ... If this case happens, one of the programs must be renamed."
So sharkdp's `fd` is fd-find's `/usr/bin/fdfind`, because fdclone has `/usr/bin/fd`, and `bat` is bat's `/usr/bin/batcat`, because bacula-console-qt has `/usr/sbin/bat`.
command-not-found reads only the Contents index, so Debian's build offers fdclone for `fd` and bacula-console-qt for `bat`.

The order follows Debian's popularity contest: the renamed package comes before the packages that have the name when it has more installations, after them when it has fewer.

```
$ fd
Command 'fd' not found, but can be installed with:
sudo apt install fd-find  # run it as 'fdfind'
sudo apt install fdclone
$ ts
Command 'ts' not found, but can be installed with:
sudo apt install moreutils
sudo apt install task-spooler  # run it as 'tsp'
```

- A command with no row is advised exactly as Debian's build advises it.
- A row whose package the database does not have is not offered.
- When the renamed program is installed already, the message says so in its place ("Command 'fd' is installed as '/usr/bin/fdfind' from deb fd-find") and lists the others.
- When the table cannot be read (missing, unreadable, a broken row), command-not-found says so in one line, with the way to restore it ("reinstalling command-not-found restores it"), and advises the command as without the table.

Shell aliases for `fd` and `bat`: none (Daniel, 2026-11-02: "why alias if there's a program that uses it? ... then we'll mess up with command-not-found").

## Every caller

bash (`command_not_found_handle` in Debian's `/etc/bash.bashrc`), zsh (`/etc/zsh_command_not_found`, sourced by sparky-stereo-console's zshrc) and fish (its own handler, in an interactive shell) print command-not-found's message, so they need nothing else.

KRunner's missing program runner and Dolphin's packs (sparky-stereo-integration 0.1.2) read the same table:
- **KRunner** offers each package command-not-found names, in its order, when one of them is a renamed one; otherwise one package, or none, as before.
- **An installed renamed program** is a KRunner match in its place, with command-not-found's line as its text. It runs the program with the query's arguments in the person's terminal, found the way KIO's KTerminalLauncherJob finds it.
- **A table that cannot be read:** command-not-found's line that says so is the subtext of each KRunner match.
- **Dolphin** offers Install for the renamed package when it comes first, and for the one other package when the renamed ones come after (`ts`: moreutils). Its dialog shows command-not-found's whole message.

sparky-stereo-integration 0.1.2 also fixes two things the tests found in the KRunner runner:
- It is enabled by default. KRunner loads a D-Bus runner only when its metadata says `X-KDE-PluginInfo-EnabledByDefault=true` or krunnerrc enables it, and 0.1.0 said neither.
- It takes two-letter commands such as `fd` (it took three letters or more).

## The table

`renamed-commands` is made by `make-renamed.py` from Debian's own data: forky's Contents and Packages indexes, Debian's popularity contest (`by_inst`), and each candidate source's `debian/README.Debian`, `debian/NEWS` and `debian/changelog` from sources.debian.org.
The script's header gives its two rules and the order rule; each row's comment names the Debian text it rests on.
Every rename that Debian's own words document is in the table.

Made on 2026-11-02 from forky's indexes of 2026-11-02 (573 candidates, 320 sources read).
The Installs column gives popularity contest installations, of the package against the most installed package that has the name:

| Command | Package | Installed as | Order | Installs | Debian's words |
|---|---|---|---|---|---|
| `antlr` | antlr | `runantlr` | first | 4,601 / 15 (pccts) | changelog: "Renamed /usr/bin/antlr to /usr/bin/runantlr because it conflicts with pccts. Closes: #127898" |
| `bat` | bat | `batcat` | first | 6,594 / 91 (bacula-console-qt) | README.Debian: "the executable and its manpage have been renamed from 'bat' to 'batcat' because of a file name clash with another Debian package" |
| `cal` | ccal | `ccal` | after | 262 / 32,443 (ncal) | README.Debian: "even though it is originally named cal, in Debian it's 'ccal' in order to avoid conflicting with bsdmaintuils package" |
| `cl` | iraf | `irafcl` | first | 172 / 41 (cl-launch) | README.Debian: "cl/ecl had to be renamed to "irafcl"" |
| `fd` | fd-find | `fdfind` | first | 5,919 / 99 (fdclone) | README.Debian: "Because /usr/bin/fd is already used by fdclone, we are install fd into /usr/lib/cargo/bin/fd and creating a symlink from this file to /usr/bin/fdfind." |
| `spline` | spline | `aspline` | after | 13 / 314 (plotutils) | changelog: "renamed spline to aspline due to file name conflict with plotutils" |
| `ts` | task-spooler | `tsp` | after | 182 / 11,341 (moreutils) | changelog: "Refresh ts to tsp renaming patch (Closes: #905902)" |
| `wipe` | lam-runtime | `lamwipe` | after | 206 / 1,948 (wipe) | changelog: "Patched lamnet.h, renaming wipe to lamwipe as in 6.3.2" |
| `xsd` | xsdcxx | `xsdcxx` | after | 40 / 2,976 (mono-devel) | README.Debian: "Due to name conflicts with mono-1.0-devel the `xsd` application was renamed to `xsdcxx`." |

To make it again:

```sh
# Debian's indexes, decompressed into DATA: Contents-<component>-<arch>.txt (the lines under bin and sbin),
# Packages-<component>-amd64, popcon-by_inst.gz (https://popcon.debian.org/by_inst.gz)
python3 -I make-renamed.py --data DATA --evidence EVIDENCE --fetch --out renamed-commands --report report.tsv
```

## Translations

The three new messages ship in the nine languages in `patches/sparky-renamed-commands.patch`.
Upstream's catalogs leave messages command-not-found prints untranslated: ten in pt_BR and zh_TW (the main header "Command '%(command)s' not found, but can be installed with:" among them) and three in ja.
`sparky-os/translations/command-not-found-messages.po.patch` fills them.
They are translated by Claude for Daniel Ramos (Capitain Jack), with pt_BR for Daniel's review.
They are an offer for upstream's translators on Launchpad.

## Build

`build.sh WORK PREVIOUS_DIR SOURCE_DIR` runs `build-in-container.sh` in the Lean Code migration container:
1. Debian's source package, checked by the hash of its `.dsc`.
2. After Debian's series: `patches/sparky-renamed-commands.patch`, a patch made from `renamed-commands`, and the translations patch.
3. The changelog entry from `changelog-sparky1.txt`.
4. The Lean Code source, then the build with Debian's own tests (`python3 -m unittest discover`, which includes `test_renamed_commands.py` and pyflakes) and the link and start gate against Debian's 23.04.0-3 build.

It needs `SPARKY_REPO_DIR` (the published tree) and `SPARKY_LC_ARCHIVE_DIR` (sparky-os/lean/archive.md).

## Tests

`tests/test-callers.sh CANDIDATES OUT IMAGE` installs today's packages in a fresh Debian testing container: Debian's command-not-found and the published sparky-stereo-integration and sparky-stereo-console, with deb-multimedia.
It probes `fd`, `bat`, `ts`, `cal` and four commands without a renamed package, in:
- bash, zsh and fish, with `-i` and in a pty session;
- the real KRunner library (`tests/krunner-query`, KRunner::RunnerManager with the default krunnerrc);
- the runner's own D-Bus Match;
- a Dolphin pack.

It then installs the candidates and probes again, and probes three more states:
- fd-find and task-spooler installed: KRunner's run match is run through RunnerManager, against a stand-in terminal.
- The table removed.
- The table at mode 000.

`tests/check-callers.py` judges each phase: red, green and unchanged; the messages in the nine languages, with real locales; and 300 sampled commands and 23 words that must stay unchanged.

## Credits

command-not-found is Zygmunt Krynicki's program (2005 to 2008), developed in Ubuntu by Michael Vogt and maintained in Debian by Julian Andres Klode (Debian's copyright file).
Ubuntu's `priority.txt` (Michael Vogt, 2009, LP: #318442) ordered packages that have the command itself; it left with the sqlite database in 2018.
The renamed names are Debian's maintainers' decisions, quoted per row in the table.
