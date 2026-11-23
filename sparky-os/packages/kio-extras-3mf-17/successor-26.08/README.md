# KIO Extras 26.08 successor

Run `../next-source.sh --debian-successor DEBIAN-INPUTS PUBLISHED-INPUTS WORK` with `SOURCE_DATE_EPOCH` set, then `lean.debian_prepare` and `dpkg-buildpackage`.
The manifest verifies both descriptors, every source component and all five published patches before applying them without fuzz.
Every patch applies unchanged to Debian 26.08.3; the original series order and catalogue strings stay intact.
The stereo layer remains a required build dependency and runtime dependency at 1.18.0 or newer, as the published thumbnail policy requires.
The new Debian packaging supplies the current libplist ABI; the edition adds no private substitute library.
