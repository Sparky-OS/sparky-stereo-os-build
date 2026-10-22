# Sparky Stereo OS: the build

This repository builds Sparky Stereo OS 9 "Mashtabba", Daniel Ramos's edition of SparkyLinux (by Paweł "pavroo" Pijanowski), based on Debian 14 "Forky".
It holds everything needed to rebuild the edition from source: the package recipes and their artwork, the kernel recipe and its patch series, the ISO build, the repository tools, Lean Code, the Secure Boot signing scripts, the translations, the package lists, our own libraries, and the development and test tools.
The edition itself, what it does and how to try it, is presented at [Sparky-OS/sparky-stereo-os](https://github.com/Sparky-OS/sparky-stereo-os).

## Where things are

| Folder | What it holds |
|---|---|
| `sparky-os/packages` | One folder per package of ours: its `build.sh`, Debian files, artwork and tests. |
| `sparky-os/upstream` | Patch series we carry for upstream programs (Qt, Krita, Kdenlive, VLC, mpv and more), with their packaging and reproduction rigs. |
| `sparky-os/media` | FFmpeg and mpv on deb-multimedia's source packages, with our stereo 3D patches. |
| `kernel` | The kernel recipe: pinned upstream tag, patch series, configuration, Lean Code build and its qualification (`kernel/qualification`). |
| `sparky-os/iso-build` | The live ISO build and its boot matrix tests. |
| `sparky-os/repo` | Indexing, signing, provenance and publishing of the apt repository, and the per-upload tools. |
| `sparky-os/release` | Lean Code migration of the whole repository, its qualification, and the move of a machine onto it. |
| `sparky-os/lean`, `sparky-os/LEAN-CODE-POLICY.md` | Lean Code: the projection of installed code and its restore path. |
| `sparky-os/secureboot` | Making a Secure Boot key, signing kernels and modules, and our public certificate. |
| `sparky-os/lists`, `sparky-os/data` | Package selections, roles and the meta-package generators. |
| `sparky-os/translations` | Translations the edition carries for KDE programs until their translation teams take them. |
| `sparky-os/apt`, `sparky-os/power-idle`, `sparky-os/stereo-oxygen`, `sparky-os/vm`, `sparky-os/tests` | Apt pinning, power and idle defaults, the stereo icon generator, the development VM, edition-wide tests. |
| `gl-stereo` | The OpenGL stereo layer for programs without stereo of their own. |
| `openxr`, `stereo-content-test`, `upstream`, `tools` | Open VR stack patches, stereo surface tests, findings and patches for FFmpeg's containers, and development tools (local KDE CI, `proof-pair`, `measure-machine`, `nvkms-query`). |
| `kwin`, `kscreen`, `libkscreen`, `plasma-wayland-protocols`, `mesa`, `linux`, `open-gpu-kernel-modules`, `egl-wayland`, `kimageformats`, `spectacle` | Our forks, as submodules on their `stereo3d` branches. |

## Settings

Tools that need a path, a host or a key read it from a local configuration file that never enters a repository.
Copy `sparky-os/config/build.conf.example` to `~/.config/sparky-stereo/build.conf` (or point `SPARKY_STEREO_CONFIG` at your copy) and fill it in; a tool stops with the name of any key it is missing.

## Sign with your own keys

Nothing here carries a private key.
`sparky-os/secureboot/make-secureboot-key.sh` makes your own Secure Boot key and `sparky-os/repo/make-signing-key.sh` your own repository key; the signing scripts take the key folder as an argument (`sign-kernel.sh`, `sign-modules.sh`, `sign-kernel-deb.sh`) or from `SPARKY_REPO_GNUPGHOME` (`publish-tree.sh`).
Our public certificate, `sparky-os/secureboot/sparky-stereo-secureboot-2026.pem`, verifies the kernels and modules we publish.

## Licence

The repository is under the GNU General Public License, version 3 or (at your option) any later version: [LICENSE](LICENSE), as the file headers say.
Packages, libraries and patches that carry their own licence keep it: their `LICENSE` or `copyright` file, and the upstream projects' own terms for patches to them.

## Credits

The packages, patches and translations credit their authors in their own copyright files and headers.
This work is built with AI assistance, directed and checked by Daniel; the [AI provenance](https://github.com/Sparky-OS/sparky-stereo-os/blob/main/docs/ai-provenance.md) page says how.
