# TCP over loopback through the paths series group 46 changed (ORDER 627): the established lookups of IPv4 and IPv6
# (4e2b3ef19e0e and its series) and the SYN cookie path (tcp_syncookies=2 makes the listener answer every SYN with a cookie,
# so each connection is completed by cookie_v4_check or cookie_v6_check and tcp_get_cookie_sock). An ordinary connection and
# a payload compared byte for byte, once without cookies and once with; with cookies the kernel's SyncookiesRecv counter must
# grow. It proves the changed paths still carry TCP; it is not a test of the race the fix closes (no reproducer is run).
bench_info release "$(uname -r)"
ip link set lo up 2>/dev/null || ifconfig lo 127.0.0.1 up
cookies_recv() {
    awk '/^TcpExt:/ { if (!h) { for (i = 2; i <= NF; i++) n[i] = $i; h = 1 } else for (i = 2; i <= NF; i++) if (n[i] == "SyncookiesRecv") print $i }' /proc/net/netstat
}
port=4240
for cookies in 0 2; do
    echo "$cookies" > /proc/sys/net/ipv4/tcp_syncookies
    for addr in 127.0.0.1 ::1; do
        port=$((port + 1))
        fam=ipv4; [ "$addr" = ::1 ] && fam=ipv6
        name=tcp_${fam}_syncookies_$cookies
        printf 'stereo3d17 %s %s\n' "$fam" "$cookies" > /run/tx
        rm -f /run/rx
        before=$(cookies_recv)
        timeout 10 nc -l -p "$port" > /run/rx 2>/dev/null &
        listener=$!
        sleep 1
        timeout 5 nc -w 3 "$addr" "$port" < /run/tx > /dev/null 2>&1
        wait "$listener"
        after=$(cookies_recv)
        if ! cmp -s /run/tx /run/rx; then
            bench_check "$name" FAIL "payload not received ($(wc -c < /run/rx 2>/dev/null || echo 0) bytes)"
        elif [ "$cookies" = 2 ] && [ "$after" -le "$before" ]; then
            bench_check "$name" FAIL "payload received but SyncookiesRecv stayed at $after"
        else
            bench_check "$name" PASS "payload received; SyncookiesRecv $before -> $after"
        fi
    done
done
echo 1 > /proc/sys/net/ipv4/tcp_syncookies
