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
