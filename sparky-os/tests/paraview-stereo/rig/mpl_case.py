#!/usr/bin/env python3
"""mpl_case.py OUT: an interactive Matplotlib figure shown with stereo_matplotlib on the rig's desktop.

A 3D axes with a tilted textured surface and three markers at known places: near (red), centre (green), far (blue).
The backend comes from MPLBACKEND. Writes OUT/predict.json (each marker's centre-camera pixel and its disparity per unit
offset, from the closed form of the module's cameras), then, after the figure is drawn, the exported .pns and .jps.
ENABLE=0 switches Enable 3D off as the toolbar's box does, after 4 s. Exits by itself after RUN seconds."""
import json
import os
import sys

import matplotlib
import matplotlib.pyplot as plt
import numpy as np

RED = os.environ.get('RED') == '1'   # Debian's Matplotlib alone: the same figure, no module
if not RED:
    import stereo_matplotlib as sm
    from stereo_matplotlib import cameras

out = sys.argv[1]
MARKERS = {'near': ((0.6, -0.6, 0.9), (1.0, 0.0, 0.0)), 'centre': ((0.0, 0.0, 0.0), (0.0, 1.0, 0.0)),
           'far': ((-0.6, 0.6, -0.9), (0.0, 0.0, 1.0))}
figure = plt.figure(figsize=(float(os.environ.get('FIGW', 9.6)), float(os.environ.get('FIGH', 7.2))), dpi=100)
ax = figure.add_subplot(projection='3d')
if os.environ.get('PROJ') == 'ortho':
    ax.set_proj_type('ortho')
x, y = np.meshgrid(np.linspace(-1, 1, 40), np.linspace(-1, 1, 40))
ax.plot_surface(x, y, 0.45 * x - 0.35 * y - 0.6, cmap='viridis', rstride=1, cstride=1, linewidth=0, antialiased=False)
for name, (p, colour) in MARKERS.items():
    ax.scatter([p[0]], [p[1]], [p[2]], s=260, c=[colour], depthshade=False, edgecolors='none')
ax.set_xlim(-1, 1); ax.set_ylim(-1, 1); ax.set_zlim(-1, 1)
ax.view_init(elev=22, azim=-55)
shown = None if RED else sm.StereoFigure(figure)
if shown:
    sm._figures[figure] = shown


def predict():
    figure.canvas.draw()
    result = {'backend': matplotlib.get_backend(), 'canvas': figure.canvas.get_width_height(physical=True), 'markers': {}}
    view_world, projection, u, v, w, z0, c = cameras._view(ax)
    scale = ax.transData.transform([[1.0, 0.0]])[0, 0] - ax.transData.transform([[0.0, 0.0]])[0, 0]
    for name, (p, colour) in MARKERS.items():
        m = cameras.eye_projection(ax, 0.0)
        vw = m @ np.array([p[0], p[1], p[2], 1.0])
        depth = vw[3] if ax._focal_length != np.inf else vw[2] / 2.0
        px = ax.transData.transform([[vw[0] / vw[3], vw[1] / vw[3]]])[0]
        result['markers'][name] = {'px': [float(px[0]), float(px[1])], 'per_offset': float(cameras.disparity_per_offset(ax, depth) * scale),
                                   'colour': colour}
    with open(os.path.join(out, 'predict.json'), 'w') as f:
        json.dump(result, f)


def exports():
    for suffix in ('pns', 'jps'):
        try:
            sm.save_stereo_figure(figure, os.path.join(out, 'figure.' + suffix))
        except Exception as error:
            print('export %s failed: %s' % (suffix, error), file=sys.stderr, flush=True)
    with open(os.path.join(out, 'exported.json'), 'w') as f:
        json.dump({'limits': shown.limits, 'area_width': shown.area.width if shown.area else None,
                   'offset': [b for a, b in shown.offsets.items()]}, f)


timer = figure.canvas.new_timer(interval=int(os.environ.get('PREDICT_MS', 3000)))
timer.single_shot = True
if not RED:
    timer.add_callback(predict)
    timer.start()
if os.environ.get('ENABLE') == '0':
    off = figure.canvas.new_timer(interval=4000)
    off.single_shot = True
    off.add_callback(lambda: shown.set_enabled(False, by_hand=True))
    off.start()
export_timer = figure.canvas.new_timer(interval=int(os.environ.get('EXPORT_MS', 9000)))
export_timer.single_shot = True
if not RED:
    export_timer.add_callback(exports)
    export_timer.start()
end = figure.canvas.new_timer(interval=int(os.environ.get('RUN', 40)) * 1000)
end.single_shot = True
end.add_callback(lambda: plt.close('all'))
end.start()
plt.show()
