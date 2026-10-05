set -e
export DEBIAN_FRONTEND=noninteractive
echo 'deb [trusted=yes] file:/repo ./' > /etc/apt/sources.list.d/sparky.list
printf 'Package: *\nPin: origin ""\nPin-Priority: 900\n' > /etc/apt/preferences.d/sparky
apt-get update -qq
apt-get -y install --no-install-recommends kwin-wayland kwin-common kwin-data libkwin6 mesa-libgallium mesa-vulkan-drivers libgl1-mesa-dri libegl-mesa0 libgbm1 python3-dbus python3-pil python3-numpy dbus dbus-x11 dbus-user-session xwayland ca-certificates >/pb/out/apt1.log 2>&1
apt-get -y install /pending/libmpv2_*stereo3d1_amd64.deb /pending/mpv_*stereo3d1_amd64.deb >/pb/out/apt2.log 2>&1
dpkg -l kwin-wayland kwin-common kwin-data libkwin6 mesa-libgallium libmpv2 mpv libstereo-declare1 2>&1 | awk '/^ii/{print $2, $3}' > /pb/out/package-versions.txt
mpv --version | head -1 >> /pb/out/package-versions.txt
chmod 777 /pb/out
useradd -u 1000 -M -d /tmp/home -s /bin/bash daniel; getent group 125 >/dev/null || groupadd -g 125 render125
