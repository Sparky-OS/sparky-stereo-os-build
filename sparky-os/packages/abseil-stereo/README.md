# Abseil compatibility package

Debian testing supplied `libabsl20260526` at `20260526.0-2+b1` for amd64 and
`20260526.0-2` for i386 on 20 October 2026. `Multi-Arch: same` requires equal
versions. Wine reaches this dependency through libgphoto2, libgd3, libavif and
libgav1, so the edition needs a coherent pair.

The native i386 tests also exposed two separate compatibility problems:

- On the edition's amd64 kernel, the 32-bit fast-syscall vDSO entry begins with
  `0f 1f 00` where its `int $0x80; ret` alternative was removed.
  The unwinder's decoder and interrupted
  PC window now start after that padding. Legacy prologues and checks remain.
- An infinite-timeout test's moving lower bound passed the 32-bit time limit.
  The test-only fix is backported from [upstream c521584590af](https://github.com/abseil/abseil-cpp/commit/c521584590af5291ca576e625525c3b16ba05c8b).
  The timeout implementation is unchanged.

Start with the authenticated Debian `20260526.0-2` source. Run `prepare.py SOURCE`,
then the edition's `lean.debian_prepare` at `20260526.0-2+stereo3d1+lc1` and build
normally. Retain the resulting source descriptor and use that exact descriptor
for both architectures. Run the native test suites and compare every shared
file of `Multi-Arch: same` packages before publication.

Keep the original failures in the build evidence. The hung signal-handler test
was stopped after its unsupported-instruction assertion; that is a failure,
not a skipped or passing test. Do not disable these tests to obtain packages.

Revisit this edition override when Debian supplies a coherent pair with the
required compatibility fixes. Preserve its ABI and ordinary library names.

The fresh `20260526.0-2+stereo3d1+lc1` builds passed all 241 native tests on
each architecture on 20 October 2026. Both builds passed the package payload/HR
checks, and all 417 shared paths across the four Multi-Arch package pairs matched.
A separate decoder fixture covered the legacy SYSENTER, SYSCALL and int80
prologues, both padded fast-syscall prologues and rejection of an unknown
instruction. These are candidate build results; repository publication and
installed Wine dependency checks are separate steps.
