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
- `Dockerfile.sbtools`: the container with `sbsigntool`.

Tested 2026-10-07 on Sparky Stereo OS's kernel package `linux-image-7.3.0-rc1-stereo3d` (version 6): unsigned before, signed after (1,752 bytes of signature), verified against the certificate.
Not tested yet: enrolment of the certificate and a signed boot in firmware (the boot-chain study's rig can do it).
