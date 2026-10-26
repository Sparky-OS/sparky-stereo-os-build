# Archive-backed runtime qualification

`lean.release check-link` resolves Debian `Depends` and `Pre-Depends` with APT and executes the loader in a filesystem containing only those verified packages and the supplied edition packages.
It never installs a package or runs maintainer scripts.
It needs Python 3, APT, dpkg-deb, readelf, nm, bubblewrap and working unprivileged user namespaces.
Use a native runner for the package architecture.

```sh
export SPARKY_LC_ARCHIVE_CONFIG=/path/to/public-sources.json
export SPARKY_LC_SCRATCH=/path/to/private-link-scratch
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
PYTHONPATH=sparky-os python3 -m lean.release check-link \
    --previous-dir /path/to/previous \
    --smoke sparky-os/lean/smoke.tsv \
    candidate.deb sibling-library.deb
```

The equivalent CLI options are `--archive-config` and `--scratch`.
`archive.example.json` explicitly selects the public Debian Forky main archive and its public distribution keyring.
Copy and change that file to match the package's declared runtime archive.
Additional public archives need their own explicit public keyring and source entry.
Workstation APT sources, pins, authentication, trust stores, hooks and installed status are excluded by an early `APT_CONFIG` bootstrap.
Missing configuration blocks qualification.
The repository publisher inherits these two variables and runs this gate before copying or signing new native or architecture-independent packages.
Foreign packages retain the publication contract's native-execution exclusion and produce an explicit unqualified-execution message.
That message does not certify their runtime behavior.

The JSON file is a nonempty list of objects with `uri`, `suite`, `components` and `keyring`.
HTTPS public sources and explicit `file:` fixture archives are accepted.
Credentials in URLs and arbitrary APT configuration directives are rejected.
For an immutable Debian snapshot use its timestamped URI, for example `https://snapshot.debian.org/archive/debian/20261025T000000Z`, the intended suite and `"check_valid_until": false` when the Release date has expired.
This option changes Release freshness checking only.
Signature and package hash checks remain mandatory.
The public keyring is copied into scratch and its hash is recorded.
No private key or workstation signing setup is needed.

APT starts from an empty scratch status database and solves the exact candidate with its explicitly supplied edition siblings available through a scratch-generated local index.
Its solver handles alternatives, epochs, Debian revisions, versioned Provides, architecture qualifiers, Architecture all, conflicts and Multi-Arch rules within the selected architecture.
Recommends and Suggests are excluded.
Local package versions are pinned and the candidate file is requested exactly, so archive packages cannot silently replace edition inputs.
Only siblings selected by the dependency solver contribute files, and those selected packages must be coinstallable and dependency-valid.
The scratch local index is trusted only for the explicitly supplied files whose identities and hashes are recorded; public archive indexes still require signature verification.
The publisher supplies the selected native and architecture-independent edition packages as that local universe, including libraries already present in the destination pool.
The optional `--siblings-file` accepts further authoritative edition `.deb` paths, one per line.
The candidate replaces a same-name input when checking its predecessor.
A predecessor whose executable or runtime libraries do not resolve in the qualified environment cannot establish a passing baseline.

Each architecture gets separate APT state and one frozen signed-index view for candidate and predecessor comparisons.
Downloads use APT's selected URL, signed size and SHA-256, then independently check the archive control identity against the signed index before extraction.
The shared scratch `sha256/` cache is content addressed and reverified on every use.
A corrupt cache entry blocks the gate and names the entry to remove before retrying.
Each comparison retains configuration, signature-verification logs, signed metadata and its hashes, solver decisions, dependency controls, exact identities, URLs, byte sizes, hashes and execution commands.
See `metadata.json`, `case-*-solve.log`, `case-*/resolution.json` and `case-*/execution.jsonl` below the reported scratch directory.
These are qualification evidence, not packages to publish.
Scratch is persistent and private to the invocation owner; remove completed run directories when their evidence is no longer needed.
The gate requires 2 GiB free on scratch in addition to the next package download.
Operators must also preserve their build host's free-space floor and allow for extracted payload size.

The extractor reads package data only and resolves absolute symlinks relative to the new root.
It rejects path escapes, differing overlapping files and special files.
The filesystem uses the merged `/usr` layout.
The loader is the interpreter from the qualified packages and uses their matching libc.
The gate passes `--inhibit-cache`, binds that root alone, clears the environment, drops capabilities, and isolates user, PID and network namespaces.
Absolute RPATH, interpreter defaults and explicit loader search paths consequently resolve inside that root.
`LD_LIBRARY_PATH`, `LD_PRELOAD`, desktop variables and workstation files cannot supply a missing runtime library.
Loader tracing with `LD_WARN` and `LD_BIND_NOW` retains unresolved-symbol checks, including the TORCS dropped-NEEDED regression.
Smoke programs also use immediate binding.
Library-only imports legitimately supplied by their application remain informational without a predecessor.
Lost stereo imports still block and lost NEEDED entries remain informational when resolution succeeds.
Static ELF files are inspected without requiring a dynamic loader, independently of locale.

The gate does not implement foreign execution, cross-architecture dependency roots, non-glibc loaders, maintainer-script effects, or package configuration services.
An explicit dependency on an unavailable architecture fails resolution; it is never satisfied by a host package.
Archives with dependencies that require an unprovided edition package fail until its exact `.deb` is supplied.
Packages whose runtime requires maintainer-script-generated files may need a separately qualified runtime fixture; this extractor does not fabricate those effects.
A headless smoke check establishes loader startup only, not GUI functionality, hardware behavior or application correctness.
An unavailable namespace runner blocks the check even when the predecessor fails identically.

Focused offline regression tests use a disposable signed fixture archive with explicit compiler-runtime input files.
Their synthetic signing key is unrelated to release signing.

```sh
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
TMPDIR=/path/to/private-test-scratch PYTHONPATH=sparky-os \
    python3 -m pytest -q sparky-os/lean/tests/test_linkcheck.py sparky-os/lean/tests/test_archive.py
```

APT configuration loading and scratch path controls follow [apt.conf(5)](https://manpages.debian.org/testing/apt/apt.conf.5.en.html).
Dependency relationships are interpreted by APT according to [Debian Policy chapter 7](https://www.debian.org/doc/debian-policy/ch-relationships.html), rather than a new package-name parser.
