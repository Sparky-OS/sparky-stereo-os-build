# SPDX-License-Identifier: MIT
"""Two parallel cameras for Matplotlib's 3D axes, and the fit of their offset to the person's depth limits.

Each eye sees the same scene from a camera moved sideways along the view's right vector.  The cameras stay
parallel (never toe-in) and the projection is sheared so the axes' centre stays on the screen plane:

    x_view' = x_view + s * c * (d - z0)

where d is a point's distance in front of the camera, z0 the distance of the axes' centre and c = 1 / z0 for a
perspective projection (a camera moved by s, its frustum shifted back at z0) or c = 1 for an orthographic one (the
shear about the camera target of the edition's orthographic plots).  The left eye uses s = -b, the right s = +b.
On screen this gives, right eye minus left eye, in Matplotlib's projected coordinates:

    perspective:  2 b e (1 / z0 - 1 / d)        e = focal length
    orthographic: 2 b (d - z0) / z0              z0 = the axes' viewing distance

so a point behind the centre gets a positive disparity (behind the screen), a nearer one a negative one, and the
vertical disparity is zero.

The offset b is never a setting.  fit() takes the largest b for which every point Matplotlib projects while it
draws the figure (data, panes, grid, ticks, labels) stays inside the person's limits on the 3D area.
"""
import contextlib

import numpy as np
from mpl_toolkits.mplot3d import proj3d
from mpl_toolkits.mplot3d.axes3d import Axes3D

__all__ = ['InternalsChanged', 'StereoCameras', 'disparity_per_offset', 'fit', 'projected_points']

_NEEDED = ((Axes3D, 'get_proj'), (Axes3D, '_roll_to_vertical'), (Axes3D, '_calc_view_axes'),
           (proj3d, 'world_transformation'), (proj3d, '_view_transformation_uvw'),
           (proj3d, '_persp_transformation'), (proj3d, '_ortho_transformation'),
           (proj3d, '_proj_transform_vec'), (proj3d, '_proj_transform_vec_clip'))


class InternalsChanged(RuntimeError):
    """The installed Matplotlib does not build its 3D projection the way this module reads it."""


def check_internals():
    missing = ['%s.%s' % (getattr(owner, '__name__', owner), name) for owner, name in _NEEDED if not hasattr(owner, name)]
    if missing:
        raise InternalsChanged('Matplotlib changed its 3D projection; missing: ' + ', '.join(missing))


def _view(ax):
    """The parts of Axes3D.get_proj (Matplotlib 3.10): (view @ world, projection, u, v, w, z0, c)."""
    box_aspect = ax._roll_to_vertical(ax._box_aspect)
    world = proj3d.world_transformation(*ax.get_xlim3d(), *ax.get_ylim3d(), *ax.get_zlim3d(), pb_aspect=box_aspect)
    centre = 0.5 * box_aspect
    elev, azim = np.deg2rad(ax.elev), np.deg2rad(ax.azim)
    ps = ax._roll_to_vertical([np.cos(elev) * np.cos(azim), np.cos(elev) * np.sin(azim), np.sin(elev)])
    eye = centre + ax._dist * ps
    u, v, w = ax._calc_view_axes(eye)
    if ax._focal_length == np.inf:
        view = proj3d._view_transformation_uvw(u, v, w, eye)
        projection = proj3d._ortho_transformation(-ax._dist, ax._dist)
        z0, c = ax._dist, 1.0
    else:
        view = proj3d._view_transformation_uvw(u, v, w, centre + ax._dist * ps * ax._focal_length)
        projection = proj3d._persp_transformation(-ax._dist, ax._dist, ax._focal_length)
        z0 = ax._dist * ax._focal_length
        c = 1.0 / z0
    return np.dot(view, world), projection, u, v, w, z0, c


def eye_projection(ax, s):
    """The projection of one camera moved by s (s = 0 is Matplotlib's own camera)."""
    view_world, projection, u, v, w, z0, c = _view(ax)
    shear = np.eye(4)
    shear[0, 2] = -s * c
    shear[0, 3] = -s * c * z0
    ax._view_u, ax._view_v, ax._view_w = u, v, w
    return projection @ shear @ view_world


class StereoCameras:
    """Give every Axes3D of a figure one eye's camera while the figure is drawn; offsets maps axes to b.
    Nothing is marked stale: a figure in interactive mode would redraw itself and draw the pair again."""

    def __init__(self, figure, offsets):
        self.figure = figure
        self.offsets = offsets
        self._saved = {}

    def __enter__(self):
        check_internals()
        for ax in self.figure.axes:
            if isinstance(ax, Axes3D):
                self._saved[ax] = ax.__dict__.get('get_proj')
        return self

    def set_eye(self, eye):
        sign = {'left': -1.0, 'right': 1.0}[eye]
        for ax in self._saved:
            b = self.offsets.get(ax, 0.0)
            ax.get_proj = (lambda ax=ax, s=sign * b: eye_projection(ax, s))

    def __exit__(self, *exc):
        for ax, own in self._saved.items():
            if own is None:
                ax.__dict__.pop('get_proj', None)
            else:
                ax.get_proj = own
        return False


def disparity_per_offset(ax, depth):
    """Right eye minus left eye, in Matplotlib's projected x, for b = 1 at the given distances."""
    _, _, _, _, _, z0, _ = _view(ax)
    depth = np.asarray(depth, dtype=float)
    if ax._focal_length == np.inf:
        return 2.0 * (depth - z0) / z0
    with np.errstate(divide='ignore'):
        return 2.0 * ax._focal_length * (1.0 / z0 - 1.0 / depth)


@contextlib.contextmanager
def _recording(figure, found):
    """Record every point Matplotlib projects with an Axes3D's own matrix while the figure is drawn."""
    matrices = {}
    saved = {}
    cubes = {}
    skipping = [0]
    for ax in figure.axes:
        if isinstance(ax, Axes3D):
            saved[ax] = ax.__dict__.get('get_proj')
            cubes[ax] = ax.__dict__.get('_transformed_cube')

            # the axis code projects all eight corners of the box to decide its layout; only the panes it draws are
            # on screen (projected_points adds their corners), so these projections are not counted
            def cube(vals, own=ax._transformed_cube):
                skipping[0] += 1
                try:
                    return own(vals)
                finally:
                    skipping[0] -= 1
            ax._transformed_cube = cube

            def get_proj(ax=ax):
                m = eye_projection(ax, 0.0)
                matrices[id(m)] = (ax, m)
                return m
            ax.get_proj = get_proj
    plain, clipped = proj3d._proj_transform_vec, proj3d._proj_transform_vec_clip

    def note(vec, M):
        if skipping[0]:
            return
        entry = matrices.get(id(M))
        if entry is None or entry[1] is not M:
            return
        ax = entry[0]
        data = np.asarray(getattr(vec, 'data', vec), dtype=float)
        if data.ndim != 2 or data.shape[0] != 4:
            return
        vw = np.dot(M, data)
        depth = vw[3] if ax._focal_length != np.inf else vw[2] / 2.0
        with np.errstate(divide='ignore', invalid='ignore'):
            x, y = vw[0] / vw[3], vw[1] / vw[3]
        ok = np.isfinite(x) & np.isfinite(y) & np.isfinite(depth) & (depth > 0)
        found.setdefault(ax, []).append(np.vstack([x[ok], y[ok], depth[ok]]))

    def plain_wrap(vec, M):
        note(vec, M)
        return plain(vec, M)

    def clipped_wrap(vec, M, *args, **kwargs):
        note(vec, M)
        return clipped(vec, M, *args, **kwargs)
    proj3d._proj_transform_vec, proj3d._proj_transform_vec_clip = plain_wrap, clipped_wrap
    try:
        yield
    finally:
        proj3d._proj_transform_vec, proj3d._proj_transform_vec_clip = plain, clipped
        for ax, own in cubes.items():
            if own is None:
                ax.__dict__.pop('_transformed_cube', None)
            else:
                ax._transformed_cube = own
        for ax, own in saved.items():
            if own is None:
                ax.__dict__.pop('get_proj', None)
            else:
                ax.get_proj = own


def projected_points(figure, renderer):
    """Draw the figure once with Matplotlib's own camera and return, per Axes3D, the points it projected:
    an array of rows (x_px, y_px, disparity_px_per_unit_offset) in the renderer's pixels."""
    found = {}
    check_internals()
    with _recording(figure, found):
        figure.draw(renderer)
    for ax in figure.axes:
        if isinstance(ax, Axes3D):
            corners = _drawn_pane_corners(ax)
            if corners is not None:
                m = eye_projection(ax, 0.0)
                vw = m @ corners
                depth = vw[3] if ax._focal_length != np.inf else vw[2] / 2.0
                found.setdefault(ax, []).append(np.vstack([vw[0] / vw[3], vw[1] / vw[3], depth]))
    result = {}
    for ax, parts in found.items():
        xyd = np.hstack(parts) if parts else np.zeros((3, 0))
        px = ax.transData.transform(np.column_stack([xyd[0], xyd[1]])) if xyd.shape[1] else np.zeros((0, 2))
        scale = ax.transData.transform([[1.0, 0.0]])[0, 0] - ax.transData.transform([[0.0, 0.0]])[0, 0]
        per_offset = disparity_per_offset(ax, xyd[2]) * scale
        result[ax] = np.column_stack([px, per_offset]) if xyd.shape[1] else np.zeros((0, 3))
    return result


def _drawn_pane_corners(ax):
    """The corners (homogeneous, 4 x N) of the panes Matplotlib draws: for each axis the plane active_pane() picks,
    in the corner order of Axes3D._transformed_cube."""
    if not ax.axison:
        return None
    columns = []
    for axis in (ax.xaxis, ax.yaxis, ax.zaxis):
        if not axis.pane.get_visible():
            continue
        mins, maxs, _, highs = axis._get_coord_info()
        i = axis._axinfo['i']
        plane = axis._PLANES[2 * i + 1] if highs[i] else axis._PLANES[2 * i]
        x0, x1, y0, y1, z0, z1 = mins[0], maxs[0], mins[1], maxs[1], mins[2], maxs[2]
        cube = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        columns += [cube[k] + (1.0,) for k in plane]
    return np.array(columns, dtype=float).T if columns else None


def fit(points, limits, size):
    """The largest offset b per axes for which every projected point inside the area (width, height) stays
    within the limits (sunk behind the screen, popped in front, both in the renderer's pixels)."""
    sunk, popped = limits
    width, height = size
    offsets = {}
    for ax, rows in points.items():
        inside = rows[(rows[:, 0] >= 0) & (rows[:, 0] <= width) & (rows[:, 1] >= 0) & (rows[:, 1] <= height)]
        per = inside[:, 2] if len(inside) else np.zeros(0)
        behind = per[per > 0].max() if np.any(per > 0) else 0.0
        front = -per[per < 0].min() if np.any(per < 0) else 0.0
        candidates = []
        if behind > 0:
            candidates.append(max(sunk, 0.0) / behind)
        if front > 0:
            candidates.append(max(popped, 0.0) / front)
        offsets[ax] = min(candidates) if candidates else 0.0
    return offsets
