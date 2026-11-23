# ORDER 428 (Claude Sonnet 5.5 lane, for Opus): checks of an upgrade proof that read apt's own Inst and Remv lines and the
# dpkg database, so a run cannot pass by testing nothing (memory no-silent-fallbacks, "Proofs that cannot lie").
# Sourced after proof-common.sh. Every check calls pass or fail from proof-common.sh; a check that cannot run is a FAIL.
# Each function is also run on planted failures by test-checks.sh (red) so the checks can be seen to fail.

# check_edition_dpkg LABEL: the dpkg and dpkg-stereo in the database are the edition's (version carries +stereo, the package
# Provides dpkg-lean-code), and `dpkg --version` says so. Writes both to the evidence.
check_edition_dpkg() {
	local label=$1 v dv prov st
	{ echo "== $label"; dpkg --version | head -1; dpkg-query -W dpkg dpkg-stereo; } | tee -a $O/edition-dpkg.txt
	v=$(dpkg-query -W -f='${Version}' dpkg 2>/dev/null) || fail "$label: dpkg is not in the database"
	case $v in *+stereo*) ;; *) fail "$label: dpkg is $v, not the edition's (+stereo)";; esac
	# `dpkg --version` prints the version without the +lc1 build mark (1.23.11+stereo3d2 for 1.23.11+stereo3d2+lc1)
	# captured first, then matched: under pipefail a `cmd | grep -q` can fail when grep leaves early and cmd gets SIGPIPE
	dv=$(dpkg --version | head -1)
	[[ $dv == *"${v%+lc1}"* ]] || fail "$label: 'dpkg --version' does not say ${v%+lc1}"
	prov=$(dpkg-query -W -f='${Provides}\n' dpkg)
	[[ $prov == *dpkg-lean-code* ]] || fail "$label: dpkg $v does not Provide dpkg-lean-code"
	st=$(dpkg-query -W -f='${db:Status-Abbrev}' dpkg-stereo 2>/dev/null)
	[[ $st == ii* ]] || fail "$label: dpkg-stereo is not installed"
	pass "$label: edition dpkg $v and dpkg-stereo $(dpkg-query -W -f='${Version}' dpkg-stereo)"
}

# check_sim_edition_dpkg SIMFILE: an apt simulation (apt-get -s) that Inst-lists dpkg offers the edition's build, never Debian's
check_sim_edition_dpkg() {
	local f=$1 l
	l=$(grep -E '^Inst dpkg ' "$f" | head -1)
	[ -n "$l" ] || fail "no 'Inst dpkg' line in $f: the edition's dpkg would not be installed (the proof would run on Debian's)"
	case $l in *+stereo*) pass "apt would install the edition's dpkg: $l";; *) fail "apt would install Debian's dpkg: $l";; esac
}

# _removals LIST ALLOW WHAT: LIST holds package names apt removes (one per line); every one must be named in ALLOW
# (one package name per line, # comments); returns 1 when one is not
_removals() {
	local list=$1 allow=$2 what=$3 bad=0 p
	while read -r p; do
		[ -n "$p" ] || continue
		if [ -f "$allow" ] && [ -n "$(grep -vE '^[[:space:]]*(#|$)' "$allow" | awk -v p="$p" '$1 == p {print $1}')" ]; then
			echo "allowed removal: $p ($(grep -E "^[[:space:]]*$p([[:space:]]|\$)" "$allow" | head -1))" | tee -a $O/checks.txt
		else echo "REMOVED, not allowed: $p ($what)"; bad=1; fi
	done <"$list"
	return $bad
}

# check_inst_remv SIMFILE ALLOWED_REMV_FILE WHAT: an `apt-get -s dist-upgrade` output (apt prints Inst and Remv lines only in
# simulations). Fails when nothing is installed or upgraded (a proof of nothing), when anything is kept back, and for every
# package apt would REMOVE unless ALLOWED_REMV_FILE lists it.
check_inst_remv() {
	local f=$1 allow=$2 what=$3 n_inst n_remv
	n_inst=$(grep -c '^Inst ' "$f"); n_remv=$(grep -c '^Remv ' "$f")
	[ "$n_inst" -gt 0 ] || fail "$what: no Inst line in $f: the upgrade installs nothing, so it proves nothing"
	if grep -q 'have been kept back' "$f"; then
		sed -n '/have been kept back/,/^[A-Za-z0-9]* [a-z]* upgraded/p' "$f" | head -20
		fail "$what: packages are kept back"
	fi
	awk '/^Remv /{print $2}' "$f" | sed 's/:[a-z0-9]*$//' | sort -u >$O/.removals
	_removals $O/.removals "$allow" "$what" || fail "$what: apt removes packages that are not in the allowed list"
	pass "$what: $n_inst Inst, $n_remv Remv (all allowed), nothing kept back"
}

# check_real_log LOG ALLOWED_REMV_FILE WHAT: the output of the real `apt-get dist-upgrade`, which has no Inst or Remv lines:
# dpkg's "Unpacking NAME (new) over (old)" lines are its installs and "Removing NAME (version)" lines its removals. Fails when
# nothing was unpacked, or when something unlisted was removed.
check_real_log() {
	local f=$1 allow=$2 what=$3 n_unp n_rem
	n_unp=$(grep -c '^Unpacking ' "$f")
	[ "$n_unp" -gt 0 ] || fail "$what: no 'Unpacking' line in $f: nothing was installed, so the run proves nothing"
	# dpkg-divert prints a removal of a diversion, not a package. Keep every
	# other Removing line subject to the package allow-list.
	awk '/^Removing \047diversion of \/.* to \/.* by [a-z0-9][a-z0-9+.-]*\047$/{next} /^Removing /{print $2}' "$f" | sed 's/:[a-z0-9]*$//' | sort -u >$O/.removals
	n_rem=$(wc -l <$O/.removals)
	_removals $O/.removals "$allow" "$what" || fail "$what: apt removed packages that are not in the allowed list"
	pass "$what: $n_unp unpacked, $n_rem removed (all allowed)"
}

# plant_conffiles OUT_LIST UPGRADED_PACKAGES_FILE: for every package that the upgrade will touch and that has an on-disk
# conffile, append a marker line (a person's edit) and write "path<TAB>sha256 after the edit" to OUT_LIST. At most 40.
plant_conffiles() {
	local list=$1 pkfile=$2 p f n=0
	: >"$list"
	while read -r p; do
		[ -n "$p" ] || continue
		while read -r f _; do
			[ -f "$f" ] && [ -w "$f" ] || continue
			printf '\n# planted by the upgrade proof (ORDER 428): a person'"'"'s edit\n' >>"$f"
			printf '%s\t%s\t%s\n' "$f" "$(sha256sum "$f" | cut -d' ' -f1)" "$p" >>"$list"
			n=$((n + 1)); [ $n -lt 40 ] || return 0
		done < <(dpkg-query -W -f='${Conffiles}\n' "$p" 2>/dev/null | awk 'NF >= 2 && $1 ~ /^\//' )
	done <"$pkfile"
}

# check_planted_conffiles LIST: after the upgrade every planted edit is still there (dpkg-stereo's projection and dpkg's
# conffile rules must keep a person's edit); the marker is the proof, the hash says whether the file was rewritten at all
check_planted_conffiles() {
	local list=$1 f h p bad=0 kept=0
	[ -s "$list" ] || fail "no conffile was planted: the conffile check proved nothing"
	while IFS=$'\t' read -r f h p; do
		if [ -f "$f" ] && grep -q 'planted by the upgrade proof (ORDER 428)' "$f"; then kept=$((kept + 1))
		else echo "LOST: a person's edit in $f (package $p)"; bad=1; fi
	done <"$list"
	[ $bad = 0 ] || fail "planted conffile edits were lost in the upgrade"
	pass "conffiles: $kept planted edits of persons survived the upgrade"
}

# check_verify LABEL LOG RC PLANTED (Opus, 2026-11-07, r1107a's first real case e): dpkg-stereo --verify reports a person's
# edit of a projected conffile as "LCCHANGED PATH (differs from its build-time payload; user edits remain untouched)" and
# exits 1, as dpkg --verify lists changed conffiles. The proof plants such edits itself (plant_conffiles), so a planted
# file reported that way is the expected result; any other problem line, a problem count that does not match the lines,
# or any other exit status is a FAIL. --deep also lists AFTERINST files (changed after the install, not projected by
# dpkg-stereo), which its own summary counts as "information, not counted": they are not problems here either.
check_verify() {
	local label=$1 log=$2 rc=$3 planted=$4 l p n=0 exp=0 other=""
	[ "$rc" = 0 ] && { pass "$label clean"; return 0; }
	[ "$rc" = 1 ] || fail "$label rc=$rc: $(tail -3 "$log")"
	while IFS= read -r l; do
		case $l in
			"dpkg-stereo: "*" projected files checked, "*) n=$(sed -n 's/.* checked, \([0-9]*\) problems\?,.*/\1/p' <<<"$l");;
			LCCHANGED\ *"user edits remain untouched)")
				p=${l#LCCHANGED }; p=${p%% (*}
				if cut -f1 "$planted" | grep -qxF -- "$p"; then exp=$((exp + 1)); else other+="$l"$'\n'; fi;;
			AFTERINST\ *"(changed after the install; dpkg-stereo did not project it, and leaves it)") ;;	# its own "information, not counted"
			# a conffile of a package without a Lean Code payload (Debian's own bash, upgraded in r1114a) that the proof planted an
			# edit in: dpkg-stereo reports it as the person's, outside its problem count; expected when planted, a FAIL otherwise
			EDITED\ *"(changed by the person: left as they made it)")
				p=${l#EDITED }; p=${p#"${p%%[![:space:]]*}"}; p=${p%% (*}
				cut -f1 "$planted" | grep -qxF -- "$p" || other+="$l"$'\n';;
			"") ;;
			*) other+="$l"$'\n';;
		esac
	done <"$log"
	[ -z "$other" ] || fail "$label rc=1, problems that are not planted person edits: $(head -3 <<<"$other")"
	[ -n "$n" ] && [ "$n" = "$exp" ] || fail "$label rc=1: $exp planted edits reported but the summary counts ${n:-no} problems"
	pass "$label: only the $exp planted person edits differ from their payload (expected, kept untouched)"
}
