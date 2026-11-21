#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""props.py: print the stereo declarations on the X server $DISPLAY as one JSON line: the root's support version and
every window that carries _KDE_NET_WM_STEREO_CONTENT* properties (its id, parent, geometry, values), by walking the tree."""
import json, sys
from Xlib import X, display
d = display.Display()
root = d.screen().root
names = ["_KDE_NET_WM_STEREO_CONTENT", "_KDE_NET_WM_STEREO_CONTENT_CLASS", "_KDE_NET_WM_STEREO_CONTENT_CHILDREN",
         "_KDE_NET_WM_STEREO_CONTENT_ONE_VIEW_SIZE", "_KDE_NET_WM_STEREO_CONTENT_CHILD_PLACE", "_KDE_NET_WM_STEREO_CONTENT_VERSION", "_KDE_NET_WM_STEREO_DEPTH_LIMITS", "WM_STATE"]
atoms = {n: d.intern_atom(n, True) for n in names}
sup = d.intern_atom("_KDE_NET_WM_STEREO_CONTENT_SUPPORTED", True)
p = root.get_full_property(sup, X.AnyPropertyType) if sup else None
out = {"supported": list(p.value) if p else None, "windows": []}
def walk(w, parent):
    try:
        found = {}
        for n, a in atoms.items():
            if not a:
                continue
            pr = w.get_full_property(a, X.AnyPropertyType)
            if pr is not None:
                found[n] = [int(v) for v in pr.value]
        if found:
            g = w.get_geometry()
            a = w.get_attributes()
            nm = w.get_wm_name()
            t = root.translate_coords(w, 0, 0)
            pg = None
            try:
                pgm = d.create_resource_object("window", parent).get_geometry() if parent else None
                pg = [pgm.x, pgm.y, pgm.width, pgm.height] if pgm else None
            except Exception:
                pass
            out["windows"].append({"id": w.id, "parent": parent, "geom": [g.x, g.y, g.width, g.height], "abs": [t.x, t.y], "parent_geom": pg, "mapped": a.map_state == X.IsViewable, "name": nm, "props": found})
        for c in w.query_tree().children:
            walk(c, w.id)
    except Exception as e:
        pass
walk(root, 0)
print(json.dumps(out, default=lambda o: o.decode("utf-8", "replace") if isinstance(o, bytes) else str(o)))
