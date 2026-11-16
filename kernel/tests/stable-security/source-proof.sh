#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# source-proof.sh SOURCE_DIR: are the TCP security fixes of series group 46 (ORDER 627) in a kernel source tree?
#
# Reads the files only; builds nothing. SOURCE_DIR is an unpacked kernel tree (an export with the series applied,
# a prepared Lean Code source, or an unpacked orig tarball). One line per check, then a summary.
#   CVE-2026-99288 (4e2b3ef19e0e): both established lookups drop an unhashed socket after taking a reference.
#   CVE-2026-98432 follow-ups: ireq->ipv6_opt (fafbc4051123) and saved_syn (2b9fd1a0abf0) freed after an RCU grace period.
#   Control: CVE-2026-98432's own fix (e3f33b0a1d89, in v7.3), present in every build from 13 on.
# Exit status: 0 every check found, 1 a check missing, 2 usage or an unreadable file.
set -eu
SRC=${1:?usage: source-proof.sh SOURCE_DIR}
missing=0
# check NAME FILE FUNCTION TEXT: TEXT must appear inside FUNCTION's body in FILE (FUNCTION empty: anywhere in FILE)
check() {
    name=$1 file=$SRC/$2 func=$3 text=$4
    [ -r "$file" ] || { echo "source-proof: cannot read $file" >&2; exit 2; }
    if [ -n "$func" ]; then
        found=$(awk -v f="$func" -v t="$text" '
            index($0, f "(") && $0 !~ /;[[:space:]]*$/ { inside = 1; depth = 0 }
            inside { if (index($0, t)) hit = 1
                     n = gsub(/\{/, "{"); depth += n; m = gsub(/\}/, "}"); depth -= m
                     if (seen && depth == 0) inside = 0; if (n) seen = 1 }
            END { print hit ? "yes" : "no" }' "$file")
    else
        if grep -qF -- "$text" "$file"; then found=yes; else found=no; fi
    fi
    if [ "$found" = yes ]; then
        echo "present  $name  ($2${func:+, $func})"
    else
        echo "MISSING  $name  ($2${func:+, $func})"
        missing=$((missing + 1))
    fi
}
check 'CVE-2026-99288 IPv4 established lookup' net/ipv4/inet_hashtables.c __inet_lookup_established \
    'hlist_nulls_unhashed_lockless(&sk->sk_nulls_node)'
check 'CVE-2026-99288 IPv6 established lookup' net/ipv6/inet6_hashtables.c __inet6_lookup_established \
    'hlist_nulls_unhashed_lockless(&sk->sk_nulls_node)'
check 'CVE-2026-98432 follow-up: ireq->ipv6_opt' net/ipv6/tcp_ipv6.c tcp_v6_reqsk_destructor \
    'kfree_rcu(inet_rsk(req)->ipv6_opt, rcu);'
check 'CVE-2026-98432 follow-up: saved_syn of a socket' include/linux/tcp.h tcp_saved_syn_free \
    'kfree_rcu(tp->saved_syn, rcu);'
check 'CVE-2026-98432 follow-up: saved_syn of a request' net/ipv4/inet_connection_sock.c __reqsk_free \
    'kfree_rcu(unrcu_pointer(req->saved_syn), rcu);'
check 'control, CVE-2026-98432 fix: inet_opt' net/ipv4/af_inet.c inet_sock_destruct \
    'kfree_rcu(rcu_dereference_protected(inet->inet_opt, 1), rcu);'
check 'control, CVE-2026-98432 fix: ireq_opt' net/ipv4/tcp_ipv4.c tcp_v4_reqsk_destructor \
    'kfree_rcu(rcu_dereference_protected(inet_rsk(req)->ireq_opt, 1), rcu);'
echo "source-proof: $missing missing in $SRC"
[ "$missing" -eq 0 ]
