FROM gl-stereo-plasma:1
USER root
RUN printf '%s\n' 'deb http://deb.debian.org/debian testing main' > /tmp/gl-stereo-sources.list && \
    apt-get -o Dir::Etc::sourcelist=/tmp/gl-stereo-sources.list -o Dir::Etc::sourceparts=- update && \
    DEBIAN_FRONTEND=noninteractive apt-get -o Dir::Etc::sourcelist=/tmp/gl-stereo-sources.list -o Dir::Etc::sourceparts=- -y --no-install-recommends install libkf6bookmarks-dev libkf6completion-dev libkf6jobwidgets-dev libfaketime libkf6solid-dev libpam0g-dev xscreensaver-gl xscreensaver-gl-extra xvfb && \
    mkdir /tmp/gl-stereo-sdk && cd /tmp/gl-stereo-sdk && \
    apt-get -o Dir::Etc::sourcelist=/tmp/gl-stereo-sources.list -o Dir::Etc::sourceparts=- download libkf6kio-dev libkscreen-dev plasma-desktop-data qml6-module-org-kde-breeze-components qml6-module-org-kde-plasma-workspace plasma-workspace-data && \
    for deb in *.deb; do dpkg-deb -x "$deb" /; done && \
    rm -rf /var/lib/apt/lists/* /tmp/gl-stereo-sources.list /tmp/gl-stereo-sdk
RUN getent passwd 1000 || useradd --uid 1000 --no-create-home gl-stereo-test
USER 1000:1000
