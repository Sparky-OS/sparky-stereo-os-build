# Secure Boot keys for Sparky kernels

Debian's Secure Boot chain is a shim signed by Microsoft, with Debian's certificate inside, and a GRUB signed by Debian.
It boots kernels signed by Debian, and kernels signed by a key the machine's owner has enrolled once: a Machine Owner Key (MOK).
SparkyLinux's own kernels and Sparky Stereo OS's kernel are not Debian's, so each distribution signs its own kernels with its own key.

Two keys, because the kernels differ (Daniel, 2026-10-07):
- **Sparky Stereo OS**: made 2026-10-07, "Sparky Stereo OS Secure Boot 2026", organisation "Sparky Stereo OS (Daniel Ramos)", valid to October 2036, SHA-256 fingerprint `6F:78:C9:36:7E:31:33:1F:3B:AA:74:D0:2F:05:B1:B2:DF:36:D8:B8:5A:C6:88:94:EB:0B:4C:53:15:60:AA:A6`. The private key stays in its private folder on the build machine; only its certificate ships.
- **SparkyLinux**: Paweł makes his own with the same script, if he wants it.

Checked on 2026-10-07: SparkyLinux's ISO boots under Secure Boot with Debian's shim 15.7 and Debian-signed GRUB, and its `linux-image-7.2.8-sparky-amd64` kernel carries no Secure Boot signature, so today it boots under Secure Boot only if the owner turns Secure Boot off.

## 1. Make the key (once)

```sh
./make-secureboot-key.sh "SparkyLinux Secure Boot 2026" "SparkyLinux (Paweł Pijanowski)" ~/.sparkylinux-secureboot
```

It writes `key.pem` (private, mode 600, in a folder of mode 700), `cert.pem` and `cert.der`, and prints the fingerprint.
It refuses to overwrite an existing key.
The key is RSA 2048 with SHA-256, the size every shim and MokManager accepts, marked for code signing and for kernel module signing.

**Keep `key.pem` private**: never in a repository, an ISO or a package; back it up offline.
Only `cert.der` and `cert.pem` are shared.

## The certificate names code signing only

shim refuses a certificate in db or in the MOK list whose extended key usage includes the Linux module signing purpose (1.3.6.1.4.1.2312.16.1.2): `verify_eku()` in shim's `verify.c` (16.1) skips it for boot images.
Certificates made by `make-secureboot-key.sh` before 2026-10-15 named both purposes, so a kernel signed with such a key does not boot through shim even when the certificate is enrolled; GRUB says "bad shim loader signature".
The kernel itself checks no key usage for modules: an enrolled code-signing certificate goes to its machine keyring and verifies modules.

Measured on 2026-10-15 in QEMU (OVMF with Secure Boot and Microsoft's keys, shim 16.1 and GRUB 2.14 from Debian, our build 8 kernel), beta-iso-lutz lane:
- with the edition's 2026-10-07 certificate enrolled through MokManager, GRUB still refused our kernel ("bad shim loader signature");
- with a test key whose certificate was re-issued by `reissue-cert.sh` (code signing only) and enrolled with `mokutil --import`, the kernel signed with it booted under Secure Boot, the kernel loaded the certificate into its machine keyring, a module signed with it loaded, and the unsigned module was refused ("Key was rejected by service");
- a module signed by the same key under the old certificate was refused ("Loading of module with unavailable key is rejected"): modules name the certificate that signed them, so they are signed again after a re-issue.

To correct an existing key, keep the key and issue a new certificate, then sign everything again:

```sh
./reissue-cert.sh ~/.sparky-stereo-secureboot "Sparky Stereo OS Secure Boot 2026" "Sparky Stereo OS (Daniel Ramos)"
./sign-kernel-deb.sh ~/.sparky-stereo-secureboot <unsigned linux-image.deb> signed/<linux-image.deb>
./sign-modules.sh ~/.sparky-stereo-secureboot <linux-headers.deb> <module tree> <signed module tree>
```

The certificate's fingerprint changes; publish the new `cert.der` and `cert.pem` here and in the ISO packer's profile.

## 2. Sign each kernel before it is published

The scripts run the signing tools (`sbsigntool`) in a throwaway Debian container, so nothing is installed on the build machine; they need Docker.

A finished `linux-image` package, signed in place with the same version, before it goes to the repository:

```sh
./sign-kernel-deb.sh ~/.sparkylinux-secureboot linux-image-7.2.8-sparky-amd64_7.2.8-9_amd64.deb signed/linux-image-7.2.8-sparky-amd64_7.2.8-9_amd64.deb
```

Or one kernel image file:

```sh
./sign-kernel.sh ~/.sparkylinux-secureboot vmlinuz vmlinuz.signed
```

Each run signs, then checks the signature against the certificate ("Signature verification OK").
Without Docker, the same two commands from `sbsigntool`: `sbsign --key key.pem --cert cert.pem --output vmlinuz.signed vmlinuz`, then `sbverify --cert cert.pem vmlinuz.signed`.

## 3. The owner enrolls the certificate once

```sh
sudo mokutil --import cert.der
```

`mokutil` asks for a one-time password.
At the next boot, shim's MokManager offers "Enroll MOK"; the owner confirms with that password.
From then on, kernels signed with the key boot under Secure Boot through Debian's shim and GRUB, with no change to the firmware's own keys.
An installer can run the import for the user and tell them what MokManager will ask.

## 4. Kernel modules

- Modules built with the kernel are signed by the kernel build's own key, which that kernel already trusts.
- DKMS modules (NVIDIA's open modules, xpadneo) are signed on the user's machine by DKMS's own key (`/var/lib/dkms/mok.key`), which the owner enrolls the same way; Debian's DKMS offers it.
- To let modules signed with the distribution key load as well, build the kernel with the certificate in its trusted keys: `CONFIG_SYSTEM_TRUSTED_KEYS="cert.pem"`.

## Files

- `make-secureboot-key.sh`: makes the key.
- `sign-kernel.sh`: signs one kernel image.
- `sign-kernel-deb.sh`: signs the kernel inside a `linux-image` package.
- `sign-modules.sh`: signs the out-of-tree modules of a module tree (a live image's DKMS modules), replacing DKMS's own signature.
- `reissue-cert.sh`: a new certificate for an existing key, code signing only.
- `Dockerfile.sbtools`: the container with `sbsigntool`.

Tested 2026-10-07 on Sparky Stereo OS's kernel package `linux-image-7.3.0-rc1-stereo3d` (version 6): unsigned before, signed after (1,752 bytes of signature), verified against the certificate.
Not tested yet: enrolment of the certificate and a signed boot in firmware (the boot-chain study's rig can do it).
