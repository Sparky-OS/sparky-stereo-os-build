#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/05
# Copyright 2026 under the GNU GPL3 License
# Creates the signing key of the Sparky Stereo repository, once, in its own GnuPG home
# (mode 700, never ~/.gnupg): an Ed25519 key that only signs (no encryption subkey), then
# prints its fingerprint and exports the public key as
#   sparky-stereo-archive-keyring.gpg   (binary: goes to /usr/share/keyrings/)
#   sparky-stereo-archive-keyring.asc   (armoured text, for the web)
# Run it yourself, in a terminal. It asks before overwriting anything.
#
# Usage: make-signing-key.sh --name "Sparky Stereo Archive Key" --email ADDRESS \
#          (--passphrase | --no-passphrase) [--expire 2y] [--home DIR] [--out DIR] [--assume-yes]
#   --name, --email  the user id shown on the key (apt shows it; the e-mail is public)
#   --expire         how long the key is valid (gpg syntax: 2y, 18m, 0 = never); when it
#                    runs out, extend it with gpg --quick-set-expire and re-export (re-run
#                    the keyring package build), or clients stop trusting the repository
#   --passphrase     gpg asks you to type one. Each publishing run asks once (gpg-agent caches
#                    it for a while); publishing cannot run unattended (cron, no terminal),
#                    but a copy of the key's files alone is useless without the passphrase
#   --no-passphrase  no passphrase. Publishing can run unattended, but anyone who can read
#                    the GnuPG home can sign as the repository: keep it mode 700, off backups
#                    that leave your machine
#   --home DIR       GnuPG home (default ~/.sparky-stereo-repo-gnupg)
#   --out DIR        where the exported public key goes (default the current folder)
#   --assume-yes     do not ask before overwriting (for tests only)
# Last update 2026/10/05
set -euo pipefail
NAME= EMAIL= PASS= EXPIRE=2y OUT=$PWD YES=0
HOME_DIR=$HOME/.sparky-stereo-repo-gnupg
usage() { sed -n '/^# Usage/,/^# Last/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
while [ $# -gt 0 ]; do
	case $1 in
	--name) NAME=$2; shift 2 ;;
	--email) EMAIL=$2; shift 2 ;;
	--expire) EXPIRE=$2; shift 2 ;;
	--passphrase) PASS=ask; shift ;;
	--no-passphrase) PASS=none; shift ;;
	--home) HOME_DIR=$2; shift 2 ;;
	--out) OUT=$2; shift 2 ;;
	--assume-yes) YES=1; shift ;;
	*) usage ;;
	esac
done
[ -n "$NAME" ] && [ -n "$EMAIL" ] && [ -n "$PASS" ] || usage
confirm() {
	[ "$YES" = 1 ] && return 0
	read -r -p "$1 [y/N] " a
	[ "$a" = y ] || [ "$a" = Y ]
}
G=(gpg --homedir "$HOME_DIR")
if [ -d "$HOME_DIR" ] && "${G[@]}" --list-secret-keys 2>/dev/null | grep -q '^sec'; then
	confirm "$HOME_DIR already holds a secret key. Create another one beside it?" || exit 1
fi
mkdir -p "$OUT"
for f in sparky-stereo-archive-keyring.gpg sparky-stereo-archive-keyring.asc; do
	if [ -e "$OUT/$f" ]; then confirm "$OUT/$f exists. Overwrite?" || exit 1; fi
done
mkdir -p "$HOME_DIR"
chmod 700 "$HOME_DIR"
GPG_TTY=$(tty 2>/dev/null || true)
export GPG_TTY
UID_STR="$NAME <$EMAIL>"
if [ "$PASS" = none ]; then
	"${G[@]}" --batch --passphrase '' --quick-generate-key "$UID_STR" ed25519 sign "$EXPIRE"
else
	"${G[@]}" --quick-generate-key "$UID_STR" ed25519 sign "$EXPIRE"
fi
FPR=$("${G[@]}" --with-colons --fingerprint "$EMAIL" | awk -F: '/^fpr:/ {print $10; exit}')
"${G[@]}" --export "$FPR" >"$OUT/sparky-stereo-archive-keyring.gpg"
"${G[@]}" --armor --export "$FPR" >"$OUT/sparky-stereo-archive-keyring.asc"
chmod 644 "$OUT"/sparky-stereo-archive-keyring.*
echo
echo "fingerprint: $FPR"
echo "public key:  $OUT/sparky-stereo-archive-keyring.gpg and .asc"
echo "publish with: SPARKY_REPO_GNUPGHOME=$HOME_DIR SPARKY_REPO_KEY=$FPR publish-tree.sh SRC DEST"
