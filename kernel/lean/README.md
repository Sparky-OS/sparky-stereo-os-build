# Retained kernel source packaging

This recipe prepares the edition's already patched Linux source for a Debian
source package, native Lean Code qualification and binary packaging. It supports
the base, x86-64-v3 and RT configurations in `../config`. It does not select or
apply the stereo patch series for you.

Start from a disposable export with no `.git` or `debian` directory. Its
`SOURCE.edition.json` must identify the accepted upstream tag and commit, the
upstream timestamp, the applied patch hashes and the flavour. `prepare.py`
checks the pinned upstream identity; the release coordinator must also verify
that the exported tree and its patch inventory match that record.

```sh
python3 kernel/lean/prepare.py /path/to/kernel-export kernel --counter 9
```

Retain the resulting source as a normal `3.0 (quilt)` Debian source package,
including its original archive, Debian archive and descriptor. Rebuild from
that descriptor in a disposable Debian testing environment with its declared
build dependencies:

```sh
dpkg-source -x linux-stereo-base_7.3.0~rc6-9+lc1.dsc source
cd source
dpkg-buildpackage -us -uc -b -j4
```

The generated Debian rules run the qualified source pass before compilation.
Reviewed inputs with other consumers remain authored: exported UAPI headers,
assembly macros, build tools, documentation and inactive architectures. The
native report records those decisions. Kbuild's generated packaging stays in
the separate object directory; the edition's source recipe remains intact.

The SMB1 and SMB2 mapping generators consume annotations in three headers:
`fs/smb/client/nterr.h`, `fs/smb/client/smberr.h` and
`fs/smb/common/smb2status.h`. Those inputs remain authored. Preparation records
their hashes and the four generated tables; configuration reruns the actual
Perl generators after source projection and compares the complete results.
An empty table fails even if its generator returned success. These comments
are machine input, and a C-only check cannot establish their equivalence.

The same check also compares the cryptographic OID registry generated from
`include/linux/oid_registry.h`, and the CPU/VMX capability-name tables generated
from `arch/x86/include/asm/{cpufeatures,vmxfeatures}.h`. Their numeric OIDs and
quoted names are semantic comments, so these headers remain authored too.
Require nonempty expected entries: a compiled kernel with an empty OID registry
can boot but reject correctly signed modules. Generator checks complement,
not replace, boot and module qualification against the final package hashes.

Modules are signed by Kbuild and checked before final package assembly. The
recipe keeps BTF information and `Module.symvers` in the headers package for
external modules. For a release image, provide `SPARKY_SIGNING_KEY_DIR` pointing
to a read-only directory containing the edition's `key.pem` and `cert.pem`.
The private key never belongs in a source archive or binary package. An unsigned
local rebuild does not require access to the edition's private signing key.

`--smoke` prepares the small packaging fixture. Passing that fixture or the
configuration checks does not qualify a full kernel. Each full flavour still
needs its native build, package/HR validation, signature and private-key absence
checks, an isolated boot, and external-module builds against its installed
headers. Physical stereo outputs require their own test. Record those results
against the exact package hashes before publication or installation.


## Installed kernel hooks and packaging revisions

The nested Kbuild packages contain the kernel install/remove hooks. Staging must
copy those scripts to `debian/<package>.<script>` templates and put `#DEBHELPER#`
after `set -e`. Leaving scripts only in `debian/<package>/DEBIAN` is insufficient:
`dh_installdeb` replaces them when `dh_installmodules` supplies fragments. The
result can pass an isolated direct boot while failing to generate an initramfs
when installed through APT.

`--packaging-revision 1` produces version `7.3.0~rc6-9.1+lc1` with `--counter 9`,
while retaining kernel release `7.3.0-rc6-stereo3d9`. This option prepares a source
recipe; it does not itself authorize reusing binaries. A packaging-only release
must prove that every compiled payload is unchanged, retain its source package,
and update and verify the Lean Code version bindings and HR companion. Never
remove the marker and project an already projected payload again.

Run `check-install-hooks.py --help` for the archive regression test. Give it a
directory containing one image and its non-HR headers per flavour, a known broken
image for the negative control, a prepared amd64 Debian container image, and a new
output directory. It executes the actual control scripts against recording hooks
in both kernel hook directories and checks arguments, `INITRD`, and the ordering
of depmod. The 2026-10-21 revision passed all 15 cases across base, v3 and RT plus
the negative control. These recording consumers do not create real boot files.

A release therefore also needs an installed upgrade check: the package transaction
must generate a readable initramfs, register the expected boot entries, retain a
fallback, and finish all required DKMS builds. An empty `dpkg --audit` alone does
not prove that the next boot is prepared. Keep physical reboot/display testing
separate from these pre-reboot checks.
