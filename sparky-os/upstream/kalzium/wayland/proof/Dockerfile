FROM debian:testing
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get -y update >/dev/null && apt-get -y install ca-certificates >/dev/null 2>&1
RUN --mount=type=bind,from=repo,target=/repo echo 'deb [trusted=yes] file:/repo ./' > /etc/apt/sources.list.d/zrepo.list \
 && printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/sparky-stereo \
 && sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources \
 && apt-get -y update 2>&1 | tail -1 \
 && apt-get -y install --no-install-recommends build-essential devscripts fakeroot dpkg-dev libavogadro-dev libstereo-declare-dev 2>&1 | tail -2 \
 && apt-get -y build-dep kalzium kubrick kalgebra analitza 2>&1 | tail -3 \
 && dpkg-query -W libavogadro-dev qt6-base-dev libgl1-mesa-dri
