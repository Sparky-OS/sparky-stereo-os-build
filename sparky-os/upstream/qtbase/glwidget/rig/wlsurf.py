#!/usr/bin/env python3
"""Surfaces of a Wayland client from WAYLAND_DEBUG=client output: role (toplevel / subsurface of N), which carry a
kde_stereo_content_v1 declaration (set_content value), the last wp_viewport destination, commit count.
usage: wlsurf.py <app.raw>"""
import re, sys
surf = {}; stereo_obj = {}; vp_obj = {}
def S(i): return surf.setdefault(i, dict(role="plain", parent=None, decl=None, dest=None, commits=0, title=None, xdg=None))
xdg_surface = {}; toplevel_of = {}
for ln in open(sys.argv[1], errors="replace"):
    m = re.search(r"wl_compositor#\d+\.create_surface\(new id wl_surface#(\d+)\)", ln)
    if m: S(int(m.group(1))); continue
    m = re.search(r"get_subsurface\(new id wl_subsurface#\d+, wl_surface#(\d+), wl_surface#(\d+)\)", ln)
    if m: s = S(int(m.group(1))); s["role"] = "subsurface"; s["parent"] = int(m.group(2)); continue
    m = re.search(r"get_xdg_surface\(new id xdg_surface#(\d+), wl_surface#(\d+)\)", ln)
    if m: xdg_surface[int(m.group(1))] = int(m.group(2)); continue
    m = re.search(r"xdg_surface#(\d+)\.get_toplevel\(new id xdg_toplevel#(\d+)\)", ln)
    if m: s = S(xdg_surface[int(m.group(1))]); s["role"] = "toplevel"; toplevel_of[int(m.group(2))] = s; continue
    m = re.search(r"xdg_toplevel#(\d+)\.set_title\(\"(.*)\"\)", ln)
    if m and int(m.group(1)) in toplevel_of: toplevel_of[int(m.group(1))]["title"] = m.group(2); continue
    m = re.search(r"kde_stereo_content_manager_v1#\d+\.create\(new id kde_stereo_content_v1#(\d+), wl_surface#(\d+)\)", ln)
    if m: stereo_obj[int(m.group(1))] = int(m.group(2)); S(int(m.group(2)))["decl"] = "declared"; continue
    m = re.search(r"kde_stereo_content_v1#(\d+)\.set_content\((\d+)\)", ln)
    if m: S(stereo_obj[int(m.group(1))])["decl"] = "set_content(%s)" % m.group(2); continue
    m = re.search(r"wp_viewporter#\d+\.get_viewport\(new id wp_viewport#(\d+), wl_surface#(\d+)\)", ln)
    if m: vp_obj[int(m.group(1))] = int(m.group(2)); continue
    m = re.search(r"wp_viewport#(\d+)\.set_destination\((-?\d+), (-?\d+)\)", ln)
    if m and int(m.group(1)) in vp_obj: S(vp_obj[int(m.group(1))])["dest"] = (int(m.group(2)), int(m.group(3))); continue
    m = re.search(r"wl_surface#(\d+)\.commit\(\)", ln)
    if m: S(int(m.group(1)))["commits"] += 1
nd = 0
for i, s in sorted(surf.items()):
    print("surface #%d  %-10s%s  declaration=%s  viewport=%s  commits=%d%s" % (i, s["role"], (" of #%d" % s["parent"]) if s["parent"] else "", s["decl"], s["dest"], s["commits"], ("  title=%r" % s["title"]) if s["title"] else ""))
    nd += s["decl"] is not None
print("declared surfaces: %d" % nd)
