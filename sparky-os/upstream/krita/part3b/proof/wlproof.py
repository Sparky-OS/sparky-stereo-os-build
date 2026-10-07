#!/usr/bin/env python3
"""wlproof.py <client.log with WAYLAND_DEBUG=1>: the stereo declarations of the client and the surfaces they are on.
Prints: number of set_content requests (and values), the surface of each kde_stereo_content_v1.create, whether it is a subsurface and of which parent,
whether it was placed below its parent, and which surface is the xdg_toplevel's."""
import re, sys
log = open(sys.argv[1], errors='replace').read().splitlines()
creates, sets, subs, below, tops, xdgs = [], [], {}, [], [], {}
for l in log:
    m = re.search(r'kde_stereo_content_manager_v1#\d+\.create\(new id kde_stereo_content_v1#(\d+), wl_surface#(\d+)\)', l)
    if m: creates.append((m.group(1), m.group(2)))
    m = re.search(r'kde_stereo_content_v1#(\d+)\.set_content\((\d+)\)', l)
    if m: sets.append((m.group(1), m.group(2)))
    m = re.search(r'wl_subcompositor#\d+\.get_subsurface\(new id wl_subsurface#(\d+), wl_surface#(\d+), wl_surface#(\d+)\)', l)
    if m: subs[m.group(2)] = (m.group(1), m.group(3))
    m = re.search(r'wl_subsurface#(\d+)\.place_below\(wl_surface#(\d+)\)', l)
    if m: below.append((m.group(1), m.group(2)))
    m = re.search(r'xdg_wm_base#\d+\.get_xdg_surface\(new id xdg_surface#(\d+), wl_surface#(\d+)\)', l)
    if m: xdgs[m.group(1)] = m.group(2)
    m = re.search(r'xdg_surface#(\d+)\.get_toplevel\(new id xdg_toplevel#(\d+)\)', l)
    if m: tops.append(xdgs.get(m.group(1)))
print('set_content requests: %d, values %s' % (len(sets), sorted(set(v for _, v in sets))))
print('kde_stereo_content_v1.create calls: %d' % len(creates))
for obj, surf in creates:
    sub = subs.get(surf)
    print('  declared surface wl_surface#%s: %s' % (surf, ('a subsurface (wl_subsurface#%s) of wl_surface#%s%s' % (sub[0], sub[1], ', placed below it' if any(b == (sub[0], sub[1]) for b in below) else '')) if sub else 'NOT a subsurface'))
    if sub: print('  its parent wl_surface#%s is %s' % (sub[1], 'an xdg_toplevel surface' if sub[1] in tops else 'not a toplevel'))
print('toplevel surfaces: %s; declared toplevels: %d' % (', '.join('wl_surface#' + t for t in tops if t), sum(1 for _, s in creates if s in tops)))
