# fwupd volume locker ownership regression

This diagnostic compiles the supplied `fu-volume-locker.c` and header unchanged against GLib, substituting a small `FuVolume` test double.
It checks that an external mount is preserved, owned mounts close exactly once, and a failed mount never authorizes unmounting.
The stale-cache case models an external mount missing from the cached mount state.
That case is an injected precondition, not evidence that UDisks or any particular firmware produced it.
This harness performs no real mounts, runs no daemon and does not establish an end-to-end ESP regression.

Build `Dockerfile` for amd64 and run the container as the invoking user, mounting only a disposable workspace read-write.
Inside that container:

```sh
python3 run.py /path/to/fwupd-source /path/to/disposable-build --cc gcc
```

Repeat with `--cc clang` and a separate output directory.
The command returns nonzero if any expectation fails and reports every case.
Use a source tree extracted from a verified Debian `.dsc`; source hashes are printed in the result.
Keep result logs outside the build repository.
