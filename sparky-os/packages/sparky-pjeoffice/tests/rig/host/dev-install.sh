#!/bin/sh
# container-side: lay the working tree of the package where its package puts it (development only; the package proofs use the .deb)
set -e
P=/pkg
install -d /usr/lib/sparky-pjeoffice /usr/share/sparky-pjeoffice/lang /usr/bin
install -m644 $P/python/*.py $P/python/merge-trust.js /usr/lib/sparky-pjeoffice/
install -m755 $P/sh/sparky-pjeoffice $P/sh/pjeoffice-pro /usr/bin/
install -m644 $P/catalogue/catalogue.json /usr/share/sparky-pjeoffice/
install -m644 $P/lang/* /usr/share/sparky-pjeoffice/lang/
sparky-stereo-problems catalog sparky-pjeoffice $P/lang /usr/lib/systemd/catalog --subject LOCAL1=LOCAL2,LOCAL3,LOCAL4,LOCAL5,LOCAL6,LOCAL7,LOCAL8,LOCAL10,LOCAL11 >/dev/null
