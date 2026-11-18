# shared helpers for the ORDER 707 proofs (sourced inside a ds707- container, root, no network)
export DEBIAN_FRONTEND=noninteractive
W=${W:-/tmp/w707}
mkdir -p "$W"
# mk_pkg NAME VERSION VALUE: two conffiles whose bytes change with VALUE, each with comments Lean Code removes
mk_pkg() {
	d=$W/$1-$2; rm -rf "$d"
	mkdir -p "$d/DEBIAN" "$d/etc/default" "$d/etc/init.d" "$d/etc/X11/Xsession.d"
	{ echo "# $1 defaults: this explanation is for people and moves to the HR copy."; for i in 1 2 3 4 5 6; do echo "# explanation line $i, which the program skips at every start."; done; echo "OPTION=$3"; } >"$d/etc/default/$1"
	{ echo '#!/bin/sh'; for i in 1 2 3 4 5 6; do echo "# init script commentary line $i, only for people."; done; echo "echo $3"; } >"$d/etc/init.d/$1"; chmod 755 "$d/etc/init.d/$1"
	{ for i in 1 2 3 4 5 6; do echo "# Xsession part commentary line $i."; done; echo "VALUE=$3"; } >"$d/etc/X11/Xsession.d/20$1"
	printf '/etc/default/%s\n/etc/init.d/%s\n/etc/X11/Xsession.d/20%s\n' "$1" "$1" "$1" >"$d/DEBIAN/conffiles"
	printf 'Package: %s\nVersion: %s\nArchitecture: all\nMaintainer: test <t@example.org>\nDescription: ORDER 707 fixture\n' "$1" "$2" >"$d/DEBIAN/control"
	dpkg-deb --root-owner-group -b "$d" "$W/$1_$2_all.deb" >/dev/null
}
modes() { stat -c '%a %U:%G %n' /usr/lib/dpkg-stereo /usr/lib/dpkg-stereo/lean; }
