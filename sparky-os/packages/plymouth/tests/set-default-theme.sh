#!/bin/bash
# Runs the real plymouth-set-default-theme on every shape of /etc/plymouth/plymouthd.conf the person can have
# and on the commands around it (ORDER 718). Plymouth's own script, only its folders redirected by the
# PLYMOUTH_* variables it reads; `id` is a stand-in so the script runs as root's check without root.
#   set-default-theme.sh SCRIPT [TABLE]
# SCRIPT is plymouth-set-default-theme (installed, or Plymouth's scripts/plymouth-set-default-theme.in);
# TABLE, if given, receives one line for each case: the name, the exit status and the file afterwards.
# Exit status: the number of cases that failed (0 when every case passed). Needs bash, sed, grep, awk, cmp, cat.
set -u
script=$(readlink -f "$1")
table=${2:-/dev/null}
work=$(mktemp -d "${TMPDIR:-/tmp}/set-default-theme.XXXXXX")
trap 'chmod -R u+rwx "$work" 2>/dev/null; rm -rf "$work"' EXIT
share=$work/share plugins=$work/plugins bin=$work/bin libexec=$work/libexec
mkdir -p "$share/plymouth/themes/alpha" "$share/plymouth/themes/zeta" "$plugins" "$bin" "$libexec/plymouth"
mkdir -p "$share/plymouth/themes/text"
for t in alpha zeta; do
	printf '%s\n' '[Plymouth Theme]' 'ModuleName=script' > "$share/plymouth/themes/$t/$t.plymouth"
done
printf '%s\n' '[Plymouth Theme]' 'ModuleName=text' > "$share/plymouth/themes/text/text.plymouth"
: > "$plugins/script.so"; : > "$plugins/text.so"
printf '%s\n' '#!/bin/sh' 'echo 0' > "$bin/id"
printf '%s\n' '#!/bin/sh' ': > "$PLYMOUTH_TEST_MARKER"' > "$libexec/plymouth/plymouth-update-initrd"
chmod +x "$bin/id" "$libexec/plymouth/plymouth-update-initrd"

failed=0 n=0 case_dir= conf= out=
# fixture NAME CONTENT: the file's bytes exactly as printf '%b' reads CONTENT; the name "-" means no file, "--" no folder
start() {
	n=$((n + 1)); name=$1
	case_dir=$work/case$n; conf=$case_dir/etc/plymouthd.conf
	rm -rf "$case_dir"; mkdir -p "$case_dir"
	[ "$2" = "--" ] || mkdir -p "$case_dir/etc"
	[ "$2" = "-" ] || [ "$2" = "--" ] || printf '%b' "$2" > "$conf"
	orig=$case_dir/orig; [ -e "$conf" ] && cp "$conf" "$orig" || : > "$orig"
}
run() {
	PLYMOUTH_DATADIR=$share PLYMOUTH_CONFDIR=$case_dir/etc PLYMOUTH_POLICYDIR=$case_dir/policy \
	PLYMOUTH_PLUGIN_PATH=$plugins/ PLYMOUTH_LIBEXECDIR=$libexec PLYMOUTH_TEST_MARKER=$case_dir/rebuilt \
	PATH=$bin:$PATH "$script" "$@" > "$case_dir/stdout" 2> "$case_dir/stderr"
	status=$?
}
log() { { printf '%s | exit %s | ' "$name" "$status"; if [ -e "$conf" ]; then od -An -c "$conf" | tr -s ' ' | tr -d '\n'; else printf 'no file'; fi; echo; } >> "$table"; }
ok() { echo "ok $n - $name"; }
bad() { echo "not ok $n - $name: $1"; failed=$((failed + 1)); }
# the value of Theme in the [Daemon] section, as ini readers see it, and how many Theme lines the section holds
daemon_theme() { awk '/^[[:space:]]*\[/ {s = ($0 ~ /^[[:space:]]*\[Daemon\][[:space:]]*$/)} s && /^[[:space:]]*Theme[[:space:]]*=/ {sub(/^[^=]*=[[:space:]]*/, ""); print}' "$1" 2>/dev/null; }
# the file without the lines this command may add or change: the trailing empty lines, a header it wrote, the Theme line
norm() { grep -vx 'Theme=alpha' "$1" | awk 'NF {for (i = 0; i < b; i++) print ""; b = 0; print; next} {b++}'; }

store() { # NAME CONTENT EXPECTED_SHAPE: shape keeps = other lines unchanged; replaces = Theme=old became Theme=alpha; headers = [Daemon] may be new
	start "$1" "$2"; run alpha; log
	[ $status -eq 0 ] || { bad "exit $status: $(cat "$case_dir/stderr")"; return; }
	[ -f "$conf" ] || { bad "exit 0 and no file"; return; }
	got=$(daemon_theme "$conf")
	[ "$got" = alpha ] || { bad "exit 0 and [Daemon] Theme is '$got'"; return; }
	[ "$(ls "$case_dir/etc")" = plymouthd.conf ] || { bad "the folder holds $(ls "$case_dir/etc" | tr '\n' ' ')"; return; }
	[ "$(grep -c '^Theme=alpha$' "$conf")" -eq 1 ] || { bad "more than one Theme line"; return; }
	if [ "$3" = replaces ]; then sed 's/^Theme=old$/Theme=alpha/' "$orig" > "$case_dir/want"; else cp "$orig" "$case_dir/want"; fi
	norm "$case_dir/want" > "$case_dir/want2"
	if grep -qx '\[Daemon\]' "$orig"; then norm "$conf" > "$case_dir/have"; else norm "$conf" | grep -vx '\[Daemon\]' > "$case_dir/have"; fi
	cmp -s "$case_dir/have" "$case_dir/want2" || { bad "other lines changed: $(diff "$case_dir/want2" "$case_dir/have" | tr '\n' '|')"; return; }
	[ "$(PLYMOUTH_DATADIR=$share PLYMOUTH_CONFDIR=$case_dir/etc PLYMOUTH_POLICYDIR=$case_dir/policy PLYMOUTH_PLUGIN_PATH=$plugins/ PATH=$bin:$PATH "$script")" = alpha ] || { bad "the command with no argument does not name alpha"; return; }
	ok
}
reset() { # NAME CONTENT: --reset removes the Theme line of [Daemon] and nothing else
	start "$1" "$2"; run --reset; log
	[ $status -eq 0 ] || { bad "exit $status: $(cat "$case_dir/stderr")"; return; }
	[ -z "$(daemon_theme "$conf")" ] || { bad "a Theme is still stored"; return; }
	grep -vx 'Theme=old' "$orig" > "$case_dir/want"
	if [ -s "$orig" ]; then cmp -s "$conf" "$case_dir/want" || { bad "other bytes changed"; return; }; fi
	ok
}

D='[Daemon]\n'
echo "TAP version 13"
store "header only" "$D" keeps
store "header only, no newline at the end" '[Daemon]' keeps
store "empty file" '' headers
store "no file" - headers
store "no folder" -- headers
store "header and another key" "${D}ShowDelay=5\n" keeps
store "header and another key, no newline at the end" "${D}ShowDelay=5" keeps
store "header and Theme=old" "${D}Theme=old\n" replaces
store "header, Theme=old and another key" "${D}Theme=old\nShowDelay=5\n" replaces
store "header and a comment" "${D}# the person's note\n" keeps
store "comments, keys and sections around Daemon" "# top\n[Other]\nTheme=other\nFoo=bar\n\n[Daemon]\n# keep this\nShowDelay=5\nDeviceTimeout=8\n\n[Last]\nBaz=1\n" keeps
store "Daemon is the last section and only the header" "[Other]\nFoo=bar\n${D}" keeps
store "Daemon is the last section, no newline at the end" "[Other]\nFoo=bar\n[Daemon]" keeps
store "no Daemon section" "[Other]\nFoo=bar\n" headers
store "another section holds a Theme" "[Other]\nTheme=other\n${D}" keeps
store "Daemon header with blank lines after" "${D}\n\n" keeps
reset "reset, header only" "$D"
reset "reset, empty file" ''
reset "reset, header and Theme=old" "${D}Theme=old\nShowDelay=5\n"
reset "reset, no file" -
reset "reset, comments and sections" "# top\n[Other]\nTheme=other\n\n${D}# keep\nTheme=old\nShowDelay=5\n[Last]\nBaz=1\n"

start "rebuild after choosing" "$D"; run alpha --rebuild-initrd; log
if [ $status -eq 0 ] && [ "$(daemon_theme "$conf")" = alpha ] && [ -f "$case_dir/rebuilt" ]; then ok; else bad "exit $status, theme '$(daemon_theme "$conf")', rebuilt $([ -f "$case_dir/rebuilt" ] && echo yes || echo no)"; fi
start "rebuild after reset" "${D}Theme=old\n"; run --reset --rebuild-initrd; log
if [ $status -eq 0 ] && [ -f "$case_dir/rebuilt" ]; then ok; else bad "exit $status, rebuilt $([ -f "$case_dir/rebuilt" ] && echo yes || echo no)"; fi
start "list" "$D"; run --list; log
if [ $status -eq 0 ] && [ "$(cat "$case_dir/stdout")" = "$(printf 'alpha\ntext\nzeta')" ]; then ok; else bad "list printed '$(cat "$case_dir/stdout")'"; fi

start "a theme that does not exist" "${D}Theme=old\n"; run nosuchtheme; log
if [ $status -ne 0 ] && grep -q nosuchtheme "$case_dir/stderr" && cmp -s "$conf" "$orig"; then ok; else bad "exit $status, stderr '$(cat "$case_dir/stderr")', file changed: $(cmp -s "$conf" "$orig" && echo no || echo yes)"; fi

start "a file the person cannot write" "${D}ShowDelay=5\n"; chmod 444 "$conf"; chmod 555 "$case_dir/etc"
ln -s alpha/alpha.plymouth "$share/plymouth/themes/default.plymouth"; run alpha; log
if [ $status -ne 0 ] && grep -q "$conf" "$case_dir/stderr" && cmp -s "$conf" "$orig" && [ -L "$share/plymouth/themes/default.plymouth" ]; then ok; else bad "exit $status, stderr '$(cat "$case_dir/stderr")', file changed: $(cmp -s "$conf" "$orig" && echo no || echo yes), legacy default link kept: $([ -L "$share/plymouth/themes/default.plymouth" ] && echo yes || echo no)"; fi
rm -f "$share/plymouth/themes/default.plymouth"
start "a file the person cannot write, reset" "${D}Theme=old\n"; chmod 444 "$conf"; chmod 555 "$case_dir/etc"; run --reset; log
if [ $status -ne 0 ] && grep -q "$conf" "$case_dir/stderr" && cmp -s "$conf" "$orig"; then ok; else bad "exit $status, stderr '$(cat "$case_dir/stderr")', file changed: $(cmp -s "$conf" "$orig" && echo no || echo yes)"; fi
start "a folder the person cannot write, no file" -; chmod 555 "$case_dir/etc"; run alpha; log
if [ $status -ne 0 ] && grep -q "$case_dir/etc" "$case_dir/stderr" && [ ! -e "$conf" ]; then ok; else bad "exit $status, stderr '$(cat "$case_dir/stderr")'"; fi

echo "1..$n"
echo "# $failed of $n failed"
exit $failed
