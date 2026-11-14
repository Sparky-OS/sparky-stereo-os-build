#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/23
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/13
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPRO="$HERE/../../repo/reproducible.py"
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=0.2.10
PACKAGE=sparky-stereo-graphics
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.graphics.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
# Build from the same tracked inputs that enter the source archive.
TOOLKIT=$(cd "$HERE/../.." && pwd)
COPY="$HERE/build-tools/copy-recipe.py"
[ -f "$COPY" ] || COPY="$HERE/../../../tools/copy-recipe.py"
python3 "$COPY" "$HERE" "$WORK/inputs"
mkdir -p "$WORK/inputs/build-tools"
cp "$COPY" "$WORK/inputs/build-tools/"
HERE=$WORK/inputs
D=$WORK/$PACKAGE
cmake -S "$HERE" -B "$WORK/build" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr -DKDE_INSTALL_LIBDIR=lib/x86_64-linux-gnu -DKDE_INSTALL_LIBEXECDIR=lib/x86_64-linux-gnu/libexec -DBUILD_TESTING=OFF >"$WORK/configure.log"
cmake --build "$WORK/build" -j"${JOBS:-4}" >"$WORK/build.log"
DESTDIR=$D cmake --install "$WORK/build" >"$WORK/install.log"
find "$D" -name '*.so' -o -path '*/kauth/libexec/sparkystereo_graphics_helper' -o -path '*/usr/bin/sparky-stereo-gpu-env' -o -path '*/usr/bin/sparky-stereo-gpu-record' | xargs strip --strip-unneeded
# the boot service is on from the start, as the edition's other services are
mkdir -p "$D/usr/lib/systemd/system/multi-user.target.wants"
ln -s ../sparky-stereo-gpu-record.service "$D/usr/lib/systemd/system/multi-user.target.wants/sparky-stereo-gpu-record.service"
# the problems are kept by the edition's one engine and shown by its session notifier (ORDER 350): the page's own
# messages, word for word from its .po files, as journal catalogs the engine reads in the person's language
mkdir -p "$D/usr/lib/systemd/catalog"
sparky-stereo-problems catalog $PACKAGE "$HERE/po" "$D/usr/lib/systemd/catalog" --domain kcm_sparkystereo_graphics \
	--context "@info" --context "@item kind of program" --context "@action:button" \
	--subject "@title notification|A graphics choice cannot be used" \
	--subject-map '{"@info %1 is a file|The machine'"'"'s GPU record, %1, could not be written. Until it is, Automatic treats this computer as not measured. Run: sudo sparky-stereo-gpu-record --apply-known": "@title notification|Graphics needs a repair", "@info %1 is an exit status|systemd could not reload its units after the Graphics page was installed (exit status %1). The boot service that writes the machine'"'"'s GPU record may not start. Run: sudo systemctl daemon-reload": "@title notification|Graphics needs a repair", "@info %1 is a file|A kept problem of the Graphics page cannot be read: %1.": "@title notification|Graphics needs a repair", "@info %1 is a program, %2 a GPU name, %3 says how it stopped|%1 stopped right after it started on %2: %3.": "@title notification|A program stopped on its GPU", "@info %1 is a program or a kind of program, %2 says why|Painting on the graphics card cannot be used for %1: %2. The windows are painted on the processor.": "@title notification|Painting on the graphics card cannot be used"}'
install -Dm644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
install -m644 "$HERE/README.md" "$D/usr/share/doc/$PACKAGE/README.md"
mkdir -p "$D/DEBIAN" "$WORK/shlibs/debian"
printf 'Source: %s\n\nPackage: %s\nArchitecture: amd64\n' "$PACKAGE" "$PACKAGE" >"$WORK/shlibs/debian/control"
PRIVATE=$(pkg-config --variable=libdir sparky-stereo-problems)
SHLIBS=$(cd "$WORK/shlibs" && dpkg-shlibdeps -l"$PRIVATE" --ignore-missing-info -O $(find "$D" -type f \( -name '*.so' -o -path '*/kauth/libexec/sparkystereo_graphics_helper' -o -path '*/usr/bin/sparky-stereo-gpu-env' -o -path '*/usr/bin/sparky-stereo-gpu-record' \)) 2>/dev/null | sed -n 's/^shlibs:Depends=//p')
DEPENDS="$SHLIBS, libqt6gui6 (= 6.11.2+dfsg-5+stereo3d20+lc1), libqt6widgets6 (= 6.11.2+dfsg-5+stereo3d20+lc1), libqt6opengl6 (= 6.11.2+dfsg-5+stereo3d20+lc1), qt6-qpa-plugins (= 6.11.2+dfsg-5+stereo3d20+lc1), libqt6waylandclient6 (= 6.11.2+dfsg-5+stereo3d20+lc1), sparky-stereo-vram-boost (>= 0.1.3), kdialog, power-profiles-daemon | tlp-pd | tuned-ppd, qml6-module-org-kde-kcmutils, qml6-module-org-kde-kirigami, sparky-stereo-problems (>= 0.1.2), sparky-stereo-problems-plasma (>= 0.1.0)"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PACKAGE
Version: $VERSION
Architecture: amd64
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: $DEPENDS
Recommends: hwdata, switcheroo-control
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Graphics page for System Settings
 Lists every graphics processor, lets the person choose which one draws the
  desktop and where players, games, browsers and other programs draw, and
  edits KDE's own per-program setting. Automatic puts players, games and any
  program started in 3D on the GPU measured best on the machine whatever the
  power profile, browsers by the power profile, and other programs on the GPU
  that draws the desktop. Also the copy-back choice of
  hardware video decoding, the GPU power switches of power-profiles-daemon,
  and the machine record shipped for measured models.
EOS
printf '%s\n' /etc/xdg/plasma-workspace/env/sparky-stereo-graphics.sh >"$D/DEBIAN/conffiles"
# The machine record (/etc/xdg/sparky-stereo-graphicsrc) is written by sparky-stereo-gpu-record, never shipped:
# at boot from the record of a known model, or by a measurement or an administrator on this machine. The maintainer
# scripts say and keep what fails (share/debian; autotests/no-fallbacks-test.sh runs them)
for m in postinst prerm postrm; do
	install -m 755 "$HERE/share/debian/$m" "$D/DEBIAN/$m"
done
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/prerm" "$D/DEBIAN/postrm"
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)

S=$WORK/$PACKAGE-$VERSION
mkdir -p "$S/debian"
COPY="$HERE/build-tools/copy-recipe.py"
[ -f "$COPY" ] || COPY="$HERE/../../../tools/copy-recipe.py"
python3 "$COPY" "$HERE" "$S"
mkdir -p "$S/build-tools"
cp "$COPY" "$S/build-tools/"
cat >"$S/debian/control" <<EOS
Source: $PACKAGE
Section: System
Priority: optional
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Standards-Version: 4.7.3
Build-Depends: git, python3, cmake, extra-cmake-modules, gettext, libkf6auth-dev, libkf6config-dev, libkf6coreaddons-dev, libkf6i18n-dev, libkf6kcmutils-dev, libkf6service-dev, pkgconf, qt6-base-dev, qt6-declarative-dev, sparky-stereo-problems (>= 0.1.2)
Rules-Requires-Root: no
Homepage: https://sparkylinux.org

Package: $PACKAGE
Architecture: amd64
Depends: \${shlibs:Depends}, libqt6gui6 (= 6.11.2+dfsg-5+stereo3d20+lc1), libqt6widgets6 (= 6.11.2+dfsg-5+stereo3d20+lc1), libqt6opengl6 (= 6.11.2+dfsg-5+stereo3d20+lc1), qt6-qpa-plugins (= 6.11.2+dfsg-5+stereo3d20+lc1), libqt6waylandclient6 (= 6.11.2+dfsg-5+stereo3d20+lc1), sparky-stereo-vram-boost (>= 0.1.3), kdialog, power-profiles-daemon | tlp-pd | tuned-ppd, qml6-module-org-kde-kcmutils, qml6-module-org-kde-kirigami, sparky-stereo-problems (>= 0.1.2), sparky-stereo-problems-plasma (>= 0.1.0)
Recommends: hwdata, switcheroo-control
Description: Graphics page for System Settings
 Every graphics processor, the main desktop GPU, where programs draw, the GPU
 measured best for players and 3D, and the copy-back choice of video decoding.
EOS
cat >"$S/debian/changelog" <<EOS
$PACKAGE ($VERSION) unstable; urgency=medium

  * ORDER 518, Paint windows (Daniel, 2026-11-11: "why can't we enhance
    qwidget to respect our gpu choice?"; 2026-11-12: "keep as a option",
    "the reason is offload the cpu load"): how programs made with Qt Widgets
    paint their windows is a choice on the page, for each kind of program
    and for each program: Automatic, On the processor, On the graphics card
    (batched), On the graphics card, Qt's OpenGL engine.
  * ORDER 554, Automatic for each program (Daniel, 2026-11-13: "I want the
    automatic per program for sure"): a program measured on this hardware to
    take at least a fifth less processor batched, in every fixed work, is
    painted batched under Automatic; a program not measured, or measured no
    better, is painted by the processor, and the page says which for each
    program. The measured record ships for the hardware that was measured
    (share/machines: a Ryzen 5 5600G with its Radeon and an RTX 3060, and
    the Lenovo ideapad 310-15ABR), one row for each program and card with
    its loads and their source ([MeasuredPaintPrograms]); nothing is guessed
    for another machine. sparky-stereo-gpu-record --set-paint PROGRAM CARD
    WAY writes a row measured on this machine.
  * sparky-stereo-gpu-env hands the launcher QT_WIDGETS_GPU_PAINT with the
    GPU's variables (--print paint, paint-reason, paint-env), and
    sparky-stereo-gpu-run applies it also when its caller chose the GPU. A
    value set by hand in the session wins, and the page says so.
  * A way that cannot be had is said and kept, and the program paints on
    the processor: before the start (no graphics processor that can draw, a
    Qt without the painting), and after it, told by the program itself
    through QT_WIDGETS_GPU_PAINT_TELL (--paint-failed, --paint-ok), with
    "Paint on the processor" (--use-paint) as the person's explicit choice.
  * Ten languages.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Sat, 14 Nov 2026 12:00:00 +0000

$PACKAGE (0.2.7) unstable; urgency=medium

  * ORDER 467 (Daniel, 2026-11-08: "I could not launch waterfox"): a program
    this page sent to a GPU that stops right after it starts is told and
    kept. The session's systemd runs every program KIO starts as
    app-NAME@ID.service and knows how it ended; a drop-in
    (/usr/lib/systemd/user/app-.service.d) runs sparky-stereo-gpu-env --died
    when such a service fails and --survived when it ends cleanly. A death is
    kept in the problems engine (key died-NAME) only for a program sent to a
    GPU, that failed within [Launch] DiedWithin (10 seconds, 0 turns it off),
    with the program's last output, and "Use NAME" for the GPU its desktop
    entry can name (--use-app, the entry's own PrefersNonDefaultGPU). The
    program is never started again; a launcher, a hand-over, a person
    closing it and a crash after the window raise nothing. The Graphics page
    lists the kept deaths. Nine languages.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Sun, 08 Nov 2026 12:00:00 -0300

$PACKAGE (0.2.6) unstable; urgency=medium

  * Add the video memory protection opt-in through KAuth and the package conffile.
  * Show VRAM problems and their translated actions from the shared engine.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Tue, 03 Nov 2026 12:00:00 -0300

$PACKAGE (0.2.4) unstable; urgency=medium

  * ORDER 350 (Daniel, 2026-11-02: "Why machinery to keep a failure for
    each?"): the problems are kept by the edition's one engine,
    sparky-stereo-problems, through its C library; the page's own notifier
    and user units go: the engine's session notifier shows each problem,
    with "Use NAME" for each GPU that can draw as the record's own actions
    (sparky-stereo-gpu-env --use KEY GPU) and Open Graphics settings.
    --problems and the Graphics page read the engine's records; --notify
    starts the session's notifier. The messages, word for word from the
    page's .po files, are built into journal catalogs. Decode on another
    GPU and the page's choices are untouched.
  * Every line sparky-stereo-gpu-env and sparky-stereo-gpu-record say is in
    the nine languages (required-languages: "It covers every string we
    add"): their usage, with the synopsis as it is, and each wrong use;
    the translations test also finds any translatable string of the
    sources that the template lacks.
  * Automatic is a rule, not the person's choice (ORDER 346g): when it
    cannot place a program now (browsers while the power profile cannot be
    read), sparky-stereo-gpu-env says and keeps it as before and exits 5,
    so Plasma's launcher (kf6-kio 6.30.0-1+stereo3d8) starts the program
    as the session would; a kind the person set to Follow the power profile
    and every chosen GPU that cannot be used still exit 4, and the launcher
    then starts nothing. sparky-stereo-gpu-run asks or does not start the
    program on 4 and on 5 alike.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Mon, 02 Nov 2026 12:00:00 -0300

$PACKAGE (0.2.3) unstable; urgency=medium

  * Nothing fails silently (Daniel, 2026-11-01; ORDER 346a): a GPU the
    person chose (by its PCI address, or Integrated or Discrete) that is not
    here, has no driver or render node, or that the account may not open,
    is never replaced by another GPU, also when one GPU is left. What
    failed, why and what to do are said in the person's language, kept in
    ~/.local/state/sparky-stereo-graphics/problems until the choice works
    again, shown as a notification at login with the GPUs that can draw as
    "Use NAME" choices, and on the Graphics page with the same buttons.
  * sparky-stereo-gpu-run starts nothing on another GPU: it asks, with a
    display, on which GPU the program starts this time, and otherwise does
    not start it (exit status 4); a missing or failing
    sparky-stereo-gpu-env is said. --choice GPU starts on a named GPU.
  * The session script says and keeps a saved main GPU that cannot draw;
    KWin's own order draws that login, and the notification offers the
    others.
  * A power profile that cannot be read is said as such, never Balanced:
    browsers on Automatic and every kind that follows the profile cannot
    be placed until it is read; an explicit --profile is honoured, a wrong
    one is a wrong argument.
  * The machine record that cannot be written fails the configuration (and
    the removal), said and kept; systemd's reload is said and kept.
  * Automatic says when the GPU measured best for the computer is not
    there, instead of "not measured".
  * Decode on another GPU ([Decoding] OtherGpu), which libmedia-gpu-route
    0.2.2 reads, is on by default (Daniel, 2026-11-02): a video the
    players' GPU cannot decode in hardware is decoded on another GPU that
    can, and that is said; turned off, it is decoded in software, and that
    is said.
  * power-profiles-daemon is a dependency, so Follow the power profile
    works on every system (Daniel, 2026-11-02); tlp-pd (TLP) and tuned-ppd
    (TuneD) provide it for the people who use those instead.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Mon, 02 Nov 2026 06:00:00 -0300

$PACKAGE (0.2.2) unstable; urgency=medium

  * Automatic split by kind (Daniel, 2026-10-24): players, games and any
    program started in 3D on the GPU measured best whatever the power
    profile; browsers by the power profile; other programs on the GPU that
    draws the desktop in every profile.
  * PrefersNonDefaultGPU=true means what KDE's launcher does with it: the
    first discrete GPU, nothing when the default GPU is discrete; the page
    calls it "The dedicated GPU".
  * An audio program without video counts as another program.
  * From an NVIDIA desktop to a Mesa GPU, name Mesa's EGL and GLX vendors.
  * sparky-stereo-gpu-run keeps a GPU its caller already chose.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Sat, 24 Oct 2026 04:03:00 -0300

$PACKAGE (0.2.1) unstable; urgency=medium

  * sparky-stereo-gpu-env --app also takes the path of a desktop file outside
    the menu (a launcher on the desktop), as Plasma's launcher (kf6-kio
    6.30.0-1+stereo3d6) asks for such a program.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Sat, 24 Oct 2026 03:25:00 -0300

$PACKAGE (0.2.0) unstable; urgency=medium

  * Automatic puts players, and any program started in 3D, on the GPU
    measured best on the machine whatever the power profile, battery
    included; the power profile keeps steering games, browsers and other
    programs; "Follow the power profile" is a choice on every kind.
  * The machine record in /etc/xdg/sparky-stereo-graphicsrc, the file
    libmedia-gpu-route reads: sparky-stereo-gpu-record writes it at boot for
    a known model (the Lenovo ideapad 310-15ABR, from ORDER 234's numbers),
    or from a measurement on the machine.
  * A "Copy decoded video back" choice on the page ([Decoding] CopyBack).
  * --3d for sparky-stereo-gpu-env and sparky-stereo-gpu-run.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Sat, 24 Oct 2026 12:00:00 -0300

$PACKAGE (0.1.0) unstable; urgency=medium

  * First release: the Graphics page, the sparky-stereo-gpu-env command, the
    sparky-stereo-gpu-run wrapper and the Plasma session script for the main GPU.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Fri, 23 Oct 2026 18:00:00 -0300
EOS
cp "$HERE/copyright" "$S/debian/copyright"
mkdir -p "$S/debian/source"
echo '3.0 (native)' >"$S/debian/source/format"
cat >"$S/debian/rules" <<'EOS'
#!/usr/bin/make -f
binary binary-arch:
	OUT=$(CURDIR)/.. bash ./build.sh
	dpkg-distaddfile $$(dpkg-parsechangelog -S Source)_$$(dpkg-parsechangelog -S Version)_amd64.deb System optional
clean:
build build-arch build-indep binary-indep:
EOS
chmod +x "$S/debian/rules"
# A native package is dated by its own newest changelog entry (ORDER 421b); the tree is normalized so the checkout time and the umask stay out
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPRO" changelog "$S/debian/changelog")}
export SOURCE_DATE_EPOCH
python3 "$REPRO" normalize "$SOURCE_DATE_EPOCH" "$S"
(cd "$WORK" && dpkg-source -b "$S")
cp "$WORK/${PACKAGE}_${VERSION}.dsc" "$WORK/${PACKAGE}_${VERSION}.tar.xz" "$OUT/"
gzip -9n -c "$S/debian/changelog" > "$D/usr/share/doc/$PACKAGE/changelog.gz"

"$TOOLKIT/repo/provenance.sh" --tree "$D"
PYTHONPATH="$TOOLKIT${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.release build-tree "$D" "$OUT"
sync
