# Private conffile verifier protocol

dpkg-stereo 0.1.32 ships `/usr/lib/dpkg-stereo/conffile-verify` and its `lean` library.
This is a read-only predicate, not a hook or a command that restores files.
The native caller and fallback reporting are separate integration steps.

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
