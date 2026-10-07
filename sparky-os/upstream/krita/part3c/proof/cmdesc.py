#!/usr/bin/env python3
"""cmdesc.py <client.log with WAYLAND_DEBUG=1>: for every surface that got a wp_color_management_surface_v1, the image description it was given
(the parametric creator's requests) and the surface's role (xdg toplevel, subsurface, other). Prints one line per surface."""
import re, sys, collections
log = open(sys.argv[1], errors='replace').read().splitlines()
mgmt = {}          # wp_color_management_surface_v1 id -> wl_surface id
creators = {}      # creator id -> list of requests
desc_of = {}       # image_description id -> creator id
setdesc = {}       # mgmt id -> list of (desc id, intent)
subs = {}; tops = set(); xdgs = {}
for l in log:
    l = re.sub(r'^\[[0-9:.]*\]\s*', '', l)
    m = re.search(r'get_surface\(new id wp_color_management_surface_v1#(\d+), wl_surface#(\d+)\)', l)
    if m: mgmt[m.group(1)] = m.group(2)
    m = re.search(r'wp_color_manager_v1#\d+\.create_parametric_creator\(new id wp_image_description_creator_params_v1#(\d+)\)', l)
    if m: creators[m.group(1)] = []
    m = re.search(r'wp_image_description_creator_params_v1#(\d+)\.(set_\w+\([^)]*\))', l)
    if m and m.group(1) in creators: creators[m.group(1)].append(m.group(2))
    m = re.search(r'wp_image_description_creator_params_v1#(\d+)\.create\(new id wp_image_description_v1#(\d+)\)', l)
    if m: desc_of[m.group(2)] = m.group(1)
    m = re.search(r'wp_color_management_surface_v1#(\d+)\.set_image_description\(wp_image_description_v1#(\d+), (\d+)\)', l)
    if m: setdesc.setdefault(m.group(1), []).append((m.group(2), m.group(3)))
    m = re.search(r'get_subsurface\(new id wl_subsurface#\d+, wl_surface#(\d+), wl_surface#(\d+)\)', l)
    if m: subs[m.group(1)] = m.group(2)
    m = re.search(r'get_xdg_surface\(new id xdg_surface#(\d+), wl_surface#(\d+)\)', l)
    if m: xdgs[m.group(1)] = m.group(2)
    m = re.search(r'xdg_surface#(\d+)\.get_toplevel', l)
    if m: tops.add(xdgs.get(m.group(1)))
for mid, surf in mgmt.items():
    role = 'subsurface' if surf in subs else ('xdg_toplevel' if surf in tops else 'other')
    ds = setdesc.get(mid, [])
    if not ds: print('wl_surface#%s (%s): get_surface, no image description set' % (surf, role)); continue
    d, intent = ds[-1]
    print('wl_surface#%s (%s): %s intent=%s' % (surf, role, ' '.join(creators.get(desc_of.get(d), ['<named/other>'])), intent))
