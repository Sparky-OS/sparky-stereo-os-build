// SPDX-License-Identifier: GPL-2.0-or-later
#include "showpolicy.h"
#include <cassert>
#include <iostream>

int main()
{
    StereoShow::Policy policy;
    assert(policy.startSeconds == 8100 && policy.cycleSeconds == 600);
    for (int idle : {0, 899, 900, 8099}) {
        assert(!policy.visible(true, true, false, idle, false));
    }
    for (int idle : {8100, 8700, 9300, 9899}) {
        assert(policy.visible(true, true, false, idle, false));
    }
    assert(!policy.visible(true, false, true, 9900, false));
    assert(policy.visible(true, true, true, 0, false));
    assert(policy.visible(true, true, true, 0, true));
    assert(!policy.visible(true, true, false, 8100, true));
    for (int idle : {0, 1200, 8100, 9900, 14400}) {
        assert(!policy.visible(false, true, false, idle, false));
        assert(!policy.visible(false, true, true, idle, false));
    }
    policy.cycleSeconds = 300;
    policy.startSeconds = 7200;
    assert(policy.visible(true, true, false, 7200, false));
    policy.enabled = false;
    assert(!policy.visible(true, true, true, 8100, false));
    std::cout << "PASS: decided idle/manual-lock AC policy, battery/display-off/inhibition and settings overrides\n";
}
