Tests of sparky-stereo-ffmpeg-fdk
=================================

The end-to-end test runs the real helper in a container: it builds FFmpeg from the source package of a test repository (about 20 to 30 minutes on 4 processors, twice: the first build and the rebuild after an update), installs the result and checks it.

Needs: docker; the proof base image `mdmo-proofbase:1` (debian:testing with deb-multimedia configured: `sparky-os/media/docker/Dockerfile.proofbase`); the packages of ffmpeg-dmo 10:9.0.2-dmo1+stereo3d2 for amd64 (and i386 for the 32-bit variant) and its source package, as built by the media-on-dmo lane (`sparky-os/media`).

    make-test-repos.sh       the test repositories (repo2: the edition's +stereo3d2; repo2-no386; repo3: repo2 plus a +stereo3d3 "update"),
                             indexed by the real repo/make-repo.sh (provenance stamps, Packages, Sources, Release with the edition's origin)
    run-tests.sh [i386]      builds the helper package and a stand-in for sparky-stereo-apt, makes the repositories if they are missing,
                             starts the container (4 processors, a 12 GB tmpfs for /var/tmp, a noexec tmpfs where a build must fail)
    inside.sh                what runs in the container; prints PASS/FAIL lines and a SUMMARY
    relabel-version.py       a copy of a .deb with another version (makes the "update" of repo3)
    test-hook.sh             the apt hook alone, with a stand-in for the build command: no local build, an older one, on battery, the same version, a failed rebuild, a rebuild already running (12 checks, seconds)
    test-pin.sh              the pin alone, with stand-in packages (amd64 and i386) and the real helper package: a pin with a leading * keeps nothing (control), the postinst writes the exact-version pin, the candidate of every package and of the 32-bit twin is the local build, full-upgrade changes nothing, removal and purge take the pin away, reinstall brings it back (45 checks, seconds; run it against an older package with PREBUILT=file.deb to see it fail)

What it proves, each with a check that can fail: nothing happens until the helper is asked; the question, and answering no; the languages (Polish, Brazilian Portuguese, the English fallback); the stops before any change (no source line, a 32-bit package the repository lacks, too little room); a build that fails (a folder where nothing can run) changes nothing and the build tools go again; apt's own question about the build tools, answered no; the build (libfdk_aac listed, HE-AAC encoded, which the native encoder cannot make, apt keeps the build: the pin names the exact version and apt's candidate for every package, the 32-bit twin too, is the local build; the 32-bit libraries in step); the update that apt update turns into a rebuild by itself, with apt keeping the old local build while it runs and the pin following the new one; --remove, which takes the pin away.

The upgrade of a computer that has our old Debian-based "-extra" libraries is tested by `../sparky-stereo-ffmpeg-transitional/test-upgrade.sh`.
