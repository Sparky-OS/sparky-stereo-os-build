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

## Real mounts in an OVMF guest

The `vm/` fixture runs a fault injection against the installed fwupd daemon and real UDisks.
Use only a throwaway Debian guest with an fstab-mounted ESP.
The cloud guest must have fwupd 2.1.8-1, UDisks 2.11.2, a C compiler, GLib development files and dbus-monitor installed.
Prevent unrelated fwupd activations inside that guest before running the matrix.

Build the library pair with `vm/build-libraries.sh SOURCE FRESH_OUTPUT` in the supplied container as UID 1000.
Its reduced-feature libraries are diagnostic artifacts, not replacement distribution packages.
Build `stale-mountpoints.c` as a shared library with `pkg-config --cflags --libs gio-2.0` and `-ldl`.
Copy that injector and the red-lib/green-lib folders into `/home/tester/order314` in the guest.
Run `setup-fixture.sh` and `run-matrix.sh` as root inside the guest.
The QEMU process itself runs as UID 1000, with no display and no physical disks attached.

OVMF supplies no ESRT entry in this fixture, so setup adds a synthetic entry through `FWUPD_SYSFSFWDIR` while bind-mounting the real guest efivarfs.
This selects the real capsule plugin's ESP discovery path.
The injector changes only the cached MountPoints result seen by fwupd.
It does not fake a Mount error or an Unmount success: both come from the actual UDisks daemon and kernel filesystem.

The five cases check stock and patched normal starts, stock and rebuilt-unpatched faulty starts, and a patched faulty start.
The matrix fails unless both unpatched faulty starts lose the mount and the patched faulty start receives AlreadyMounted without calling Unmount or losing the mount.
The initial and final mountinfo entries, raw daemon logs and independent D-Bus monitor trace remain in the guest's fixture folder for collection.
This demonstrates the injected ownership failure, not its occurrence on particular physical firmware.
