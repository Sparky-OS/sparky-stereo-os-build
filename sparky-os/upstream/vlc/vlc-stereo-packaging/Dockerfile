# Build image for VLC Stereo: a freshly updated debian:testing with Debian's build dependencies of vlc,
# the PipeWire development files and libstereo-declare-dev from the Sparky Stereo repository (mounted at /repo while building the image).
# docker build --build-context ... is not needed: the repository directory is copied into the image's build context, see README.
FROM debian:testing
ENV DEBIAN_FRONTEND=noninteractive
COPY repo /repo
RUN apt-get update -qq && apt-get install -y -qq dpkg-dev && cd /repo && dpkg-scanpackages . /dev/null > Packages \
 && echo 'deb [trusted=yes] file:/repo ./' > /etc/apt/sources.list.d/sparky-dev.list \
 && sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources \
 && apt-get update -qq && apt-get install -y -qq devscripts quilt fakeroot git libstereo-declare-dev libpipewire-0.3-dev pkgconf lintian \
 && apt-get build-dep -y -qq vlc && apt-get clean
