# Private conffile verifier protocol

dpkg-stereo 0.1.32 ships `/usr/lib/dpkg-stereo/conffile-verify` and its `lean` library.
This is a read-only predicate, not a hook or a command that restores files.
The native caller records its decisions in /var/lib/dpkg-stereo/conffile-events; the post-invoke hook transfers refusals to the problems engine.

The native dpkg caller must first validate the current SHA-256 and the pristine original's SHA-256 and MD5 against its owning package's Conffiles entry.
Only then may it invoke the verifier at the fixed absolute path compiled into dpkg.
The path is in the running system, even for `dpkg --root`; no code is executed from the target root.
The caller must check root ownership, regular executable type, and absence of group/other write permission, including protected parent directories, before executing the checked file descriptor without a shell or PATH lookup.
Neither the record nor an environment variable may choose the executable.

Arguments, without option parsing:

```
conffile-verify PACKAGE PATH MD5_ORIGINAL SHA_ORIGINAL SHA_LEAN CURRENT_FD
```

`PATH` is the logical absolute conffile path, not its physical path under `--root`.
The compressed pristine original is an inherited regular file descriptor on standard input.
`CURRENT_FD` names another inherited regular file descriptor, at least 3, opened on the installed conffile.
Both must be positioned at offset zero.
The caller retains its own Conffiles MD5 as `MD5_ORIGINAL`; the record's md5_orig is not an authority.
The verifier rechecks all three digests to detect changed bytes between native checks and its own reads.
Input is bounded by dpkg-stereo's 4 MiB projection limit.

Python starts at `/usr/bin/python3` with `-IBS`: isolated imports, no cache writes, and no site initialization.
The library path is fixed; its parents, sources and caches must be root-owned and not group/other writable, without symlinks.
The shared `lean.conffile` comparison selects the reader from the original and path and compares the rendered bytes exactly with the installed bytes.
There is no handler argument.
The renderer runs with `check=False`, matching the existing --verify rerender check; the initial projection's consumer qualification remains separate.
An audit hook refuses filesystem changes and subprocesses; a reader requiring either is refused and must fall back to Debian's comparison.

| Exit | Meaning |
| --- | --- |
| 0 | Exact projection of the independently validated original |
| 10 | Original MD5 or SHA-256 mismatch |
| 11 | Current SHA-256 mismatch |
| 12 | Render refused, unreadable input, corrupt xz or size limit |
| 13 | Current bytes differ from this renderer's output |
| 14 | Renderer library ownership, mode or type is not trusted |
| 15 | Invalid request or nonregular input descriptor |

Success writes nothing to stdout or stderr.
Refusals write a reason and detail to stderr; stdout remains empty.
Other nonzero exits and signals are failures, never acceptance.
The native caller must preserve Debian's prompt/force-option behavior on every refusal, including a missing or untrusted executable.
dpkg-stereo's problems engine must retain the fallback reason and the actual location of the new package's conffile; the verifier itself must not write that record.

An upgraded renderer is loaded on each invocation.
The helper does not remember earlier acceptances or accept an older render merely because its record matches.
Older output that the installed renderer does not reproduce is refused with exit 12 or 13.
The native transaction tests must cover both a renderer changed in the same dpkg run and one changed in an earlier run.

The native caller exports DPKG_LEAN_CODE_VERSION=2 only to its invoke hooks.
Pre-invoke skips restoration only when both that running-binary signal and dpkg-query's installed Provides field advertise capability 2.
An older running binary therefore keeps restoration even if its database already describes a newer dpkg.

An idle configure checks the existing package snapshot first. When no recorded
conffile has a pending owner, dpkg will compare none, so pre-invoke returns
without starting the capability query. Runs that can compare a conffile still
require both capability predicates.

The older-dpkg restoration path and explicit restore also use the shared
comparison before writing. The original must match the owning package's
Conffiles entry, or its own md5sums and installed version for other files;
its path must occur in that owner's file list. Hashes in the projection record
alone never authorize restoration. A refusal keeps the current bytes and is
reported through the existing hook or restore problem. Removed conffiles retain
0.1.31's config-files check and exact reproduction before restoration; pending
unpacked owners retain their records for the later configure operation.

The journal uses package, hex-encoded logical path and numeric reason, separated by tabs.
Reason 0 clears a previous refusal, 16 marks duplicate records and 17 marks failed execution; 10 through 15 have the meanings above.
Native appenders and the hook reader hold an exclusive flock.
The hook truncates consumed events only after the problems engine keeps or clears their result.
A failed engine leaves the journal for the next post-invoke.
The hook names existing .dpkg-dist/.dpkg-new files, or says when package bytes are installed at the original path or neither candidate remains.
Repair only rechecks the conffile; it does not merge or overwrite it.

## Where the trust walk fails, and what dpkg-stereo says and does (ORDER 707)

Exit 14 has two callers.
dpkg's native caller refuses first, before it runs anything, when a step of `/`, `/usr`, `/usr/lib`, `/usr/lib/dpkg-stereo`, `/usr/lib/dpkg-stereo/conffile-verify` is not root-owned, can be written by its group or by others, is not a folder where a folder is due, or is not an executable file at the end (leancode_verifier_open in src/main/archives.c).
The verifier then walks `/usr/lib/dpkg-stereo/lean` and everything under it the same way (library_trusted).
Neither check is weakened: a folder that its group can write is refused.

dpkg keeps the mode of a folder it finds, so a folder an early package shipped group-writable stays so through every upgrade.
dpkg-stereo 0.1.0 to 0.1.7 were built with the build user's umask and shipped `/usr/lib/dpkg-stereo` and its `lean` folder as 0775; the recipe has set `umask 022` since 0.1.8 and, since 0.1.42, `chmod 0755` on every folder it ships.

Since 0.1.42:
- the preinst of an upgrade and the postinst take the group and other write permission off what root owns under `/usr/lib/dpkg-stereo`, and touch nothing outside it;
- the refusal in the problems store names the folder or file that fails and the check (mode, owner, type, missing, not executable), found by `conffile_events.trust_findings`, which walks the same steps;
- `dpkg-stereo --repair` sets the same tree right when it is not, says what it set, and settles a refused conffile whose bytes are its package's own or the exact projection of its package's original; it never writes a conffile, and a folder outside `/usr/lib/dpkg-stereo`, an entry another user owns and a link are named and left.
