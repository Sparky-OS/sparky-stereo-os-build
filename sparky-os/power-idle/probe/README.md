# Power and console verification

The main session runs the guest-only `guest-tty.py` positive and negative
modes as described in [GUEST-TTY.md](GUEST-TTY.md). It takes the output JSON
path as its first argument and returns nonzero on a mismatch. No extra
packages are required in the development guest.

Hibernate with the Cushion Swap File: `guest-hibernate.py`,
`guest-hibernate-setup.sh` and the Cushion Swap File's log on a real system,
`guest-log.py`, are described in [GUEST-HIBERNATE.md](GUEST-HIBERNATE.md).

Milestone 6's container runner is `run-power-defaults.sh`. Supply freshly
extracted Debian packages `power-profiles-daemon`, `systemd-zram-generator`,
`systemd`, `udev` and their libraries under `POWER_DEFAULTS_NATIVE_ROOT`.
The container also needs Python 3 with Gio/dbus, procps, dpkg-dev, diffutils
and dbus-daemon. Run as the workstation UID with four CPUs, a passwd entry
for that UID, and only this workspace writable. No host bus/device is used.

To prepare the native root inside a Debian amd64 container, use a writable
APT lists/cache directory under the workspace. With `apt-get` options
`Dir::State::lists`, `Dir::Cache` and `APT::Sandbox::User` pointing to those
directories and the container's UID name, run `apt-get update` and
`apt-get download` for:

```text
power-profiles-daemon systemd-zram-generator systemd udev
python3-dbus python3-gi libglib2.0-0t64 libsystemd0 libsystemd-shared
libgcc-s1 libstdc++6 libudev1 libpolkit-gobject-1-0 libgudev-1.0-0 libupower-glib3
```

Extract each downloaded archive with `dpkg-deb -x` into the same native
root. These are downloads and extraction, not installation. The checked
versions and SHA256 hashes are in `../evidence/power-defaults/inputs.json`.
PyYAML is needed only for the separate contributor-skill validator.

```sh
export POWER_DEFAULTS_NATIVE_ROOT=/workspace/work/m6/root
export POWER_DEFAULTS_WORK=/workspace/work/m6/final
export POWER_DEFAULTS_OUT=/workspace/pending-pack
export KERNEL_SETTINGS_DEB=/read-only-repo/sparky-stereo-kernel-settings_20261009.1~sparky9~0_all.deb
bash /workspace/edition/sparky-os/power-idle/probe/run-power-defaults.sh
```

`POWER_DEFAULTS_WORK` must be fresh. The meta-generator reads the repository
index via its existing `REPO` setting, defaulting to the development repo;
mount that repository read-only. The runner leaves native outputs and JSON
for review. It asserts the three negative controls fail for the expected
reason. It does not apply sysctls, initialize zram or invoke swapon.
Sources, current values and limits are in [POWER-DEFAULTS.md](../POWER-DEFAULTS.md).

Existing native Plasma readers are `run-timeline-in-container.sh` and
`run-migration-in-container.sh`; the headless timeline is documented in
[runtime/README.md](runtime/README.md). These are accepted milestone 1's
settings/runtime fixtures, separate from the development VM console proof.
