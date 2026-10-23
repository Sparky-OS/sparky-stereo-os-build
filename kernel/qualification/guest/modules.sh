# Loadability of the modules NEXT-BUILD.md names after a build: vkms and the four Realtek rtw89 USB/PCIe modules of the edition's fragment.
# The host passes them in --load-modules; this script reports whether each one is in /proc/modules.
bench_info release "$(uname -r)"
for m in vkms rtw89_8852au rtw89_8852cu rtw89_8922au rtw89_8922de; do
    if grep -q "^$m " /proc/modules; then bench_check "module_$m" PASS "loaded"; else bench_check "module_$m" FAIL "not loaded"; fi
done
