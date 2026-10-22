# SPDX-License-Identifier: GPL-2.0-or-later
# Boot 0: nothing to do. The firmware's variable store settles on its first boots (boot entries, memory it allocates), and the memory map the
# kernel sees can change with it; hibernation needs the same map in both boots, so the bench boots once before the real boots.
bench_info warmup "$(uname -r)"
