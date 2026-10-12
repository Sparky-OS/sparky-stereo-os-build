# How KDE's CI runs, and `kde-ci-local`

Read from the sources on 2026-10-06: `sysadmin/ci-utilities` (templates, `run-ci-build.py`, `components/`), `sysadmin/repo-metadata` (`branch-rules.yml`, `projects-invent/`) and `sysadmin/ci-images`.

## What a pipeline is

A fork's `.gitlab-ci.yml` only `include:`s templates from `sysadmin/ci-utilities/gitlab-templates/`; the jobs live there.
Each job is a few shell lines run in an image:

| Job (template) | Image | What it does |
| --- | --- | --- |
| `reuse` (reuse-lint) | `fsfe/reuse:5` | `rm -rf po/ poqm/`, `reuse lint` |
| `clang_format`, `xml`, `yaml`, `json-validation` | Docker `suse-qt611` | `run-clang-format.py` (clang-format 18, ECM's `.clang-format` if the repo has none), `validate-xml-files.py`, `yamllint`, `validate-json-files.py` |
| `qml-lint` | `debian:latest` | greps QML for single-quoted `i18n('...')` |
| `cppcheck` | Docker `suse-qt611` | `run-cppcheck.py` |
| `suse_tumbleweed_qt611` (linux-qt6) | VM `storage.kde.org/vm-images/suse-qt611` | `run-ci-build.py --platform Linux/Qt6/Shared` |
| `suse_tumbleweed_qt613` (linux-qt6-next) | VM `suse-qt613` (Qt 6.13 from `KDE:Qt:Next`) | the same, `Linux/Qt6Next/Shared` |
| `freebsd150_qt611` | VM `freebsd150-qt610` | the same, `FreeBSD/Qt6/Shared`, clang |
| `alpine_qt611` | arm64 VM | the same on musl |
| flatpak, snap, craft (Windows, Android, macOS), `test_ossfuzz_*` | their own images | packaging and cross builds; `deploy`/`publish` stages, manual or skipped on forks |

The Docker image `invent-registry.kde.org/sysadmin/ci-images/suse-qt611` and the VM image are built from the same `build.sh` ("system provisioning shared with the VM build"), so the Docker one is the same system.
Only the Qt 6.13 image has no Docker twin.

## What `run-ci-build.py` does

1. Reads `global.yml`, then the repo's `.kde-ci.yml`, then `config/<project>.yml` (merged; a list in `.kde-ci.yml` replaces the default).
2. `git fetch` of **all** the fork's branches into `refs/heads/*` (needed to resolve `@same`).
3. Resolves `Dependencies` (and `RuntimeDependencies`) of the platform to `(project, branch)` pairs (below), then **downloads prebuilt packages** of exactly those pairs from the package registry `teams/ci-artifacts/<platform>` on invent (anonymous read) and unpacks them into `_install/`; the packages' own recorded dependencies are fetched transitively.
   Nothing is built from source here, and the only packages in the registry are those published by KDE's own pipelines (publishing needs `KDECI_GITLAB_TOKEN`, which fork pipelines do not have: `if gitlabToken is not None and not arguments.skip_publishing`).
4. `cmake` Debug, `-DBUILD_TESTING=ON`, `-DBUILD_COVERAGE=ON`, ASAN, `-DFETCHCONTENT_FULLY_DISCONNECTED=ON`, the options of `.kde-ci.yml`; `cmake --build`; `cmake --install` (staged); then `ctest` under Xvfb + a D-Bus session; failing tests fail the job when `require-passing-tests-on` names the platform; a crash fails it (`require-no-crashes`).

## Dependency branches (`.kde-ci.yml`, `Dependencies.py`, `branch-rules.yml`)

- A requirement is a **repository path of a KDE project** (`frameworks/kio`, `plasma/libkscreen`), matched by glob against `repo-metadata/projects-invent/**/metadata.yaml`; no match raises "Unable to resolve dependency requirement" (only `third-party/` paths are exempt, and they resolve to nothing).
  So a library of ours (`stereo-declare`) can never be a dependency: there is no project for it and no package of it in the registry.
- A literal branch (`master`, `Plasma/6.7`) is used as written.
- `@same`: the branch of the project being built.
  If the ref is protected (`CI_COMMIT_REF_PROTECTED`, true only for the fork's default branch) or the pipeline is a merge request into a protected branch, that name; otherwise `_resolveSameBranch` takes the branches of the checkout that match `master`, `kf5`, `kf6` or **`.*[0-9]\.[0-9]+$`** and contain the branch's first commit, prefers `master`, else the highest.
  Any branch of ours that ends in digits.digits (`stereo3d-6.7`, `stereo3d-26.04`, `Frameworks/6.28`) is taken for a release branch and asked of the registry: "Package milou was not found in branch stereo3d-6.7".
- `@latest`, `@stable`, `@latest-kf6`, `@stable-kf6`, `@oldstable-kf6`: the rule tables of `branch-rules.yml`, looked up by repository path, exact entry first, then glob.
  Today: `@latest-kf6` gives `master` for `frameworks/*`, `plasma/*`, `libraries/mpvqt`, `libraries/plasma-wayland-protocols`; `@stable-kf6` `plasma/*` is `Plasma/6.8`, `@oldstable-kf6` `plasma/*` is `Plasma/6.7`; `@latest` and `@stable` are the Qt 5 tables (`frameworks/*` is `kf5`).
  They change when KDE releases, so a branch that must stay on 6.7 names `Plasma/6.7` literally.
- **A fork cannot be told to take a dependency from another fork**: the only inputs are repo path and branch name, and the only source is `retrieve(identifier, branch)` over the registry's package list (`Package.py`, `raise Exception(f"Package {identifier} was not found in branch {branch}")`).
  A dependent repository is therefore always built against KDE's version of its dependency, and must compile with it.

## `kde-ci-local`

`tools/kde-ci-local/kde-ci-local [TREE] [--branch B] [--ci-name NAME] [--jobs all|lint|build|a,b] [--list] [--keep] [--only-build]`

It reads the tree's `.gitlab-ci.yml`, resolves the templates from a fresh `ci-utilities`, and runs each job's own script lines in the job's image (Docker, `--platform linux/amd64`, your uid, `--cpus 4`, `cpu_count()` capped at 4 for `run-ci-build.py` and ctest), on a clean checkout of the branch's commit with the fork's branches under their pushed names.
The package cache is kept between runs (`$KDE_CI_LOCAL_WORK/cache`, default `/K3D/temp/kde-ci-local`).
`--ci-name` is the name the branch has on invent when the local one differs (`stereo3d-6.7` for the clone's `stereo3d`).
Build-job trees are deleted after the run (`--keep` keeps them); logs stay in `$KDE_CI_LOCAL_WORK/logs`.
Exit status 0 only when every job that can run passed; the last lines say GREEN or RED.

What cannot run here, and what is done instead:

- `freebsd150_qt611` (FreeBSD VM): the dependency resolution is run against the **FreeBSD** package registry (every package of the pair list must exist: this reproduces the `@same` failures exactly), then the same build with the same flags and clang on the SUSE image, without sanitizers and without the tests (those are the SUSE jobs').
  Not covered: libc++ headers, FreeBSD's own packages and paths.
- `suse_tumbleweed_qt613`: needs `kde-ci-local --build-qt613-image` once (KDE's own `suse-qt613/build.sh` on `opensuse/tumbleweed`, about 12 GB, 15 minutes); until then it is listed as skipped. Manual jobs (`when: manual`, oss-fuzz) run only when named with `--jobs`.
- `alpine_qt611` (arm64 VM), Windows, Android, macOS, flatpak, snap, craft, oss-fuzz: skipped, listed with the reason.
- Accessibility UI tests (`selenium-webdriver-at-spi-run`: KInfoCenter's `kinfocenter_appiumtests`, kdeplasma-addons' `calculatortest`, and tests that start KWin on a private bus such as `alternatecalendartest`) need a systemd user instance to start `at-spi-dbus-bus.service`; the containers have none, so they fail here on unpatched code too (measured on KInfoCenter master, 2026-10-08: "Failed to start at-spi-dbus-bus.service via systemd!"). Read them against a run of the unpatched tag or branch, never as ours by default.
- Pipelines on invent also see packages published after a local run; the registry is read live each time, so a local run and the pipeline an hour apart agree (checked on Dragon: the two logs differ only in the order of stdout and stderr lines).
- What the VM gives a job and Docker does not, added to the SUSE containers: a user runtime directory (`/run/user/1000` as tmpfs, `XDG_RUNTIME_DIR`; the pipeline's `DBUS_SESSION_BUS_ADDRESS` is `unix:path=/run/user/1000/bus`) and the host's render node (KWin's integration tests skip without one).
  Still missing, so these KWin tests fail here with or without our change: `kwin-testGameController` (needs `/dev/uinput`), `kwin-testDrm`, `-testDrmLegacy`, `-testDrmNoModifiers` (need a KMS device; they skip in `initTestCase` and then crash in teardown).
  Compare with a run of the upstream tag before reading these as ours.
  The DRM tests open `/dev/dri/card1` when `CI` is set: on KDE's VM runners that is a vkms device. Our kernel ships vkms as a module (from the next kernel build; for 7.3.0-rc1-stereo3d build 6 it was built out of tree, `/K3D/temp/vkms-build/vkms.ko`), and when it is loaded the harness passes its card into the SUSE containers as `/dev/dri/card1`. **On a desktop host this is not enough** (tried 2026-10-06): the session's KWin takes the new vkms card as one more GPU and holds DRM master on it (it also adds its Virtual-1 output, which Daniel disabled), so the test's KWin gets `Failed to authenticate the drm magic token ... Permission denied`; and the container's `/sys` is the host's, so `card1` resolves to the host's `card1` and its render node (`renderD129`, not passed). The DRM tests need a machine where nothing else holds the vkms card: a VM, or a host without a running session. Until then KDE's runners are their gate (174/174 on `suse_tumbleweed_qt613` for 3cc95b72e2). `/dev/uinput` is not passed either: the game controller test would create input devices on the host's running session.
  `kwin-testScreenshotStereo` (our test) fails here with the host's AMD render node (captures 640x240 where 320x240 is expected) and passes on KDE's runners: 174/174 on `suse_tumbleweed_qt613` for 3cc95b72e2 (job 5139183, 2026-10-06). Read it as local until it is reproduced on a virtual render node.
- `--only-build --keep` stops after the build and keeps `_build`/`_install` under `$KDE_CI_LOCAL_WORK/trees` for looking into a failure by hand.

## Krita (`linux-build-qt6`)

Krita's pipeline does not look like the KDE-wide one: its `.gitlab-ci.yml` has no `include:` of the shared templates, its jobs come from `build-tools/ci-scripts/*.yml` and run in Krita's own image, `krita-appimage-2204` (Ubuntu 22.04, built from `sysadmin/ci-images`; no image is published).
`kde-ci-local --build-krita-image` builds it once (about 2.6 GB); the job then runs like any other (`kde-ci-local TREE --branch B --ci-name NAME --project krita --jobs linux-build-qt6`).

**Krita's workflow runs branch pipelines only for the default branch, `krita/*` and release branches, and for merge requests** (the `workflow: rules:` in `.gitlab-ci.yml`; a branch with an open merge request gets the merge request pipeline only).
A fork branch that is pushed with no merge request gets no pipeline at all, so the local run is our gate before a merge request: run it on the branch head, and read it green before opening one.
Scheduled, nightly and release jobs (`linux-build-qt5-nightly`, `linux-release-qt6`, the AppImage upload) are listed but not run by `--jobs all|build`; `--jobs` with a name runs them on request.
The job builds Krita with its bundled dependencies (40 to 80 minutes with 4 cores, as measured below), runs the 317 ctest tests and packs an AppImage (upload skipped).
13 of the 317 tests fail in this image and the job still passes (`TestSvgParser*`, `kis_cage_transform_worker_test`, `kis_transform_mask_test`, `TestResourceStorage`, `StoryboardModelTest`, `kis_tiff_test`, `kis_jpegxl_test`, `SvgTextCursorTest`); the failing set was identical on both branches below, but no run of Krita's unpatched tag was made, so those 13 are not yet shown to be upstream's own.

Python bindings: the image's `pip` installs the newest PyQt6, whose SIP needs ABI 13.8 or newer, while Krita's `SIPMacros.cmake` pins 13.0, so `sipkritapart0.cpp` fails with "v13.8 is the minimum ABI version but v13.0 is being targeted". The pin is in Krita's tree, not in our change: the job fails on any branch without the `sparky/pyqt6-sip-abi` commit, which is why `sparky/deep-colour-canvas` is run on `sparky/deep-colour-canvas-ci` (the same commits plus that one).

| Date | Branch | Result |
|---|---|---|
| 2026-10-06 | `sparky/deep-colour-canvas` (a2ed3e8, alone) | RED at the SIP step above, before any of our code is compiled into the bindings |
| 2026-10-06 | `sparky/pyqt6-sip-abi` (73268e8) | PASS (GREEN), 78 min, 13 of 317 tests fail |
| 2026-10-06 | `sparky/deep-colour-canvas-ci` (a2ed3e8 + the SIP commit) | PASS (GREEN), 40 min, the same 13 tests fail |
| 2026-10-06 | `sparky/stereo-painting` (a83d04f, on the SIP and 16-bit commits) | PASS (GREEN), 41 min, 13 of 317 tests fail (one sub-test of `KisShapeLayerTest` differs between runs) |

## Known runner problems (not ours)

- **flatpak-amd64: `lsetxattr(security.selinux): Operation not supported`** at "Initializing build dir", before anything is built. Seen on KAlgebra's own master (job 5110331, node3-vmrunner, 2026-10-01) and on our fork (jobs 5137748, 5137761, 5137812, node1-vmrunner, 2026-10-06); Kubrick's flatpak passed on node2-vmrunner. Reported to KDE's sysadmins as [T18903](https://phabricator.kde.org/T18903) (2026-10-06). Retry the job; no commit of ours can fix it. **Resolved 2026-10-07 by Ben Cooksley (KDE sysadmin):** the image used for building Flatpaks carried a Flatpak version with a severe regression (Red Hat bug 2528386); Fedora shipped a fix and the image was rebuilt.
- **flatpak-amd64: "Failed to download sources: ... Operation too slow"**: a network timeout fetching a module's sources; a retry passes (Kubrick, 2026-10-06).

## Build jobs take turns (2026-10-08)

Every job whose script runs `run-ci-build` (the build-and-test jobs) takes one shared lock first, `/K3D/temp/kde-ci-local/heavy-job.lock` (`KDE_CI_LOCAL_HEAVY_LOCK` overrides it), and holds it until its tree is removed. Lanes running CI at the same time therefore queue their build jobs instead of filling `/K3D` together: three lanes' KDE CI trees (10 to 20 GB each) took it below its 20 GB floor twice on 2026-10-08 and stopped the Android build and the KWin lane. Lint jobs do not wait. The lock is taken read-only, so sandboxed lanes can wait on it too.

## One dependency cache for all lanes (2026-10-09)

KDE's dependency artifacts go to one cache, `/K3D/temp/kde-ci-local/cache` (`KDE_CI_LOCAL_CACHE` overrides it), whatever work folder a lane uses; before this every lane kept its own copy (6.8, 4.7 and 1.6 GB next to the shared 20 GB). Build jobs take turns through the shared lock, so the cache is never written by two jobs at once. Lanes that run CI get the cache as an extra writable root (`.writable-roots`).
The cache itself lives on the build disk, `/mnt/build/kde-ci-local/cache`, and the old path is a link to it (moved 2026-10-09, when it reached 20 GB and pushed /K3D under its floor); lanes get both paths as writable roots.

A lane's sandbox can show `/sys` but hide `/dev/dri`. The tool still passes the render node (and a vkms card) to the container, because Docker opens the device on the host; the group comes from `/etc/group` then.


## Our stack: one set of patched libraries for every job (2026-10-11)

KDE's `run-ci-build.py` can only take a dependency from KDE's package registry, so a fork that needs our libkscreen or our plasma-wayland-protocols cannot even build there (measured below).
`stacks/*.yml` defines the stack: the forks other projects build against, their branches and what each needs.
`kde-ci-local --stack stacks/plasma-6.7.yml` builds them once and lays them over KDE's packages in every build job; KDE's scripts stay unmodified.

```
kde-ci-local --stack stacks/plasma-6.7.yml --stack-status   # members, commits, keys, built or not
kde-ci-local --stack stacks/plasma-6.7.yml --stack-build    # build what is missing, then stop
kde-ci-local --stack stacks/plasma-6.7.yml --stack-prune    # remove prefixes of superseded keys
kde-ci-local TREE --branch B --project P --stack stacks/plasma-6.7.yml --jobs suse_tumbleweed_qt611
```

- **Members** (plasma-6.7): `plasma-wayland-protocols`, then `libkscreen` (needs it), `kimageformats`. A member is a fork that another job builds against. KWin and KScreen are consumers: they get the stack, nothing builds against them.
- **Key** of a member: first 12 hex digits of sha1 over its name, its commit, the Docker image id of the job, and the keys of the members it needs. Moving a commit changes its key and the keys of what needs it, and nothing else. KDE's own packages are not in the key (the registry moves under us), so a prefix can be older than KDE's current packages; `--stack-prune` plus a rebuild refreshes it.
- **Build** of a member: its own `.gitlab-ci.yml` job (`suse_tumbleweed_qt611`) with `--only-build` (no tests), with the members it needs laid over KDE's packages. The staged install (`_staging/.../_install`) is kept in `$KDE_CI_LOCAL_WORK/stack/NAME/members/MEMBER-KEY/prefix`. Build jobs take the shared lock as every build job does.
- **Overlay**: the composed prefix (`stack/NAME/compose/CKEY`, the members' files hard-linked into one folder, mounted read-only) is laid over `_install` by `stack-run-ci-build`, which runs KDE's `run-ci-build.py` in the same process with two wrapped calls: the registry's packages of the stack's projects are dropped before they are unpacked (so nothing of KDE's version stays, directly or through another package's recorded dependencies), and the overlay is copied in before the environment is made from `_install` (again after the runtime dependencies are unpacked). In a stack job the script line `python3 ci-utilities/run-ci-build.py ...` becomes `python3 /kdecilocal-tools/stack-run-ci-build ci-utilities/run-ci-build.py ...`; everything else is the job's own.
- A job of a member leaves out that member and the members that need it; other jobs get all members. A job on another platform than the stack's (`suse-qt6.11`) is skipped with a note.
- **Moving to Plasma 6.8**: copy the file, change `branch` and `ci-name` of each member. Nothing else is branch-specific.
- Disk: a member build is checked for 6 GB (a consumer job for 8 GB) before it starts; below the floors of /K3D (20 GB) and / (12 GB) it stops with `STATUS: blocked`.

### The same stack on invent (2026-10-11)

A fork-only CI commit puts a fork's `suse_tumbleweed_qt611` job on the stack with the steps `kde-ci-local --stack` runs: `stack-ci-commit TREE --stack stacks/plasma-6.7.yml --use libkscreen,kimageformats [--exclude PROJECT]` adds `.stack-ci/` (`stack-ci`, `stack-run-ci-build`, `kdecistack.py`, `stack.yml`) and replaces the job's script by KDE's own lines with two changes: `stack-ci prepare` before the build, and `run-ci-build.py` run through `stack-run-ci-build`.
`stack-ci prepare` resolves the members' branches with `git ls-remote`, computes the same keys, and takes each prefix from the generic package registry of `registry-project` when a package `NAME-KEY/prefix.tar.xz` exists, else builds it with KDE's script.
`--publish-job` adds a manual job `stack_publish` that builds all members and uploads them (`CI_JOB_TOKEN`).
`--job-env` and `--job-mount` let kde-ci-local give a job container the variables and mounts of a test: `STACK_CI_GIT_BASE`, `STACK_CI_REGISTRY`, `STACK_CI_WORK`, `CI_JOB_TOKEN`.
