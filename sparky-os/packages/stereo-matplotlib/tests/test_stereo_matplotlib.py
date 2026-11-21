# SPDX-License-Identifier: MIT
"""Tests that fail when the cameras, the fit or the marks are wrong (each was run against a broken form once)."""
import io
import os
import struct
import tempfile
import unittest

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

import stereo_matplotlib as sm  # noqa: E402
from stereo_matplotlib import cameras, writers  # noqa: E402

# three markers at known places, coloured so each eye can be read: near (red), centre (green), far (blue)
MARKERS = {'near': ((0.5, 0.5, 0.95), (1.0, 0.0, 0.0)), 'centre': ((0.0, 0.0, 0.0), (0.0, 1.0, 0.0)),
           'far': ((-0.5, -0.5, -0.95), (0.0, 0.0, 1.0))}


def scene(proj='persp', focal=None):
    figure = plt.figure(figsize=(6.4, 4.8), dpi=100)
    ax = figure.add_subplot(projection='3d')
    ax.set_proj_type(proj, focal_length=focal) if proj == 'persp' else ax.set_proj_type('ortho')
    for name, (p, colour) in MARKERS.items():
        ax.scatter([p[0]], [p[1]], [p[2]], s=120, c=[colour], depthshade=False, edgecolors='none')
    ax.set_xlim(-1, 1); ax.set_ylim(-1, 1); ax.set_zlim(-1, 1)
    ax.view_init(elev=20, azim=-50)
    ax.set_axis_off()
    return figure, ax


def project(ax, s, point):
    m = cameras.eye_projection(ax, s)
    v = m @ np.array([point[0], point[1], point[2], 1.0])
    return ax.transData.transform([[v[0] / v[3], v[1] / v[3]]])[0]


def depth_of(ax, point):
    m = cameras.eye_projection(ax, 0.0)
    v = m @ np.array([point[0], point[1], point[2], 1.0])
    return v[3] if ax._focal_length != np.inf else v[2] / 2.0


def closed_form(ax, b, d):
    view_world, projection, u, v, w, z0, c = cameras._view(ax)
    scale = ax.transData.transform([[1.0, 0.0]])[0, 0] - ax.transData.transform([[0.0, 0.0]])[0, 0]
    if ax._focal_length == np.inf:
        return scale * 2 * b * (d - z0) / z0
    return scale * 2 * b * ax._focal_length * (1 / z0 - 1 / d)


def centroid(picture, colour):
    rgb = picture[..., :3].astype(int)
    target = (np.array(colour) * 255).astype(int)
    mask = np.all(np.abs(rgb - target) < 40, axis=2)
    ys, xs = np.nonzero(mask)
    return xs.mean(), ys.mean(), mask.sum()


def read(path):
    with open(path, 'rb') as f:
        return f.read()


class Cameras(unittest.TestCase):
    def check_projection(self, proj, focal=None):
        figure, ax = scene(proj, focal)
        figure.canvas.draw()
        b = 0.05
        for name, (p, _) in MARKERS.items():
            left, right = project(ax, -b, p), project(ax, b, p)
            self.assertAlmostEqual(right[1] - left[1], 0.0, places=9, msg='vertical disparity at ' + name)
            self.assertAlmostEqual(right[0] - left[0], closed_form(ax, b, depth_of(ax, p)), places=6, msg=name)
        centre = MARKERS['centre'][0]
        self.assertLess(abs(project(ax, b, centre)[0] - project(ax, -b, centre)[0]), 1e-6, 'centre on the screen')
        near, far = MARKERS['near'][0], MARKERS['far'][0]
        self.assertLess(project(ax, b, near)[0] - project(ax, -b, near)[0], 0, 'near point crossed')
        self.assertGreater(project(ax, b, far)[0] - project(ax, -b, far)[0], 0, 'far point uncrossed')
        plt.close(figure)

    def test_perspective(self):
        self.check_projection('persp')

    def test_perspective_long_lens(self):
        self.check_projection('persp', 0.4)

    def test_orthographic(self):
        self.check_projection('ortho')

    def test_internals(self):
        cameras.check_internals()


class Fit(unittest.TestCase):
    def test_binding_limit(self):
        figure, ax = scene()
        renderer = figure.canvas.get_renderer()
        points = cameras.projected_points(figure, renderer)
        self.assertIn(ax, points)
        self.assertEqual(len(points[ax]), 3, 'the three markers, nothing else, with the axes off')
        size = (renderer.width, renderer.height)
        for sunk, popped in ((10.0, 4.0), (20.0, 8.0), (4.0, 10.0)):
            b = cameras.fit(points, (sunk, popped), size)[ax]
            per = points[ax][:, 2]
            inside = (points[ax][:, 0] >= 0) & (points[ax][:, 0] <= size[0]) & (points[ax][:, 1] >= 0) & (points[ax][:, 1] <= size[1])
            d = b * per[inside]
            self.assertLessEqual(d.max(), sunk + 1e-9)
            self.assertGreaterEqual(d.min(), -popped - 1e-9)
            self.assertTrue(abs(d.max() - sunk) < 1e-9 or abs(d.min() + popped) < 1e-9, 'one limit binds')
        plt.close(figure)

    def test_axes_box_is_measured(self):
        figure, ax = scene()
        ax.set_axis_on()
        points = cameras.projected_points(figure, figure.canvas.get_renderer())
        self.assertGreater(len(points[ax]), 50, 'panes, grid, ticks and labels are projected and counted')
        plt.close(figure)

    def test_undrawn_corner_not_counted(self):
        figure, ax = scene()
        ax.set_axis_on()
        renderer = figure.canvas.get_renderer()
        points = cameras.projected_points(figure, renderer)[ax]
        m = cameras.eye_projection(ax, 0.0)
        corners = [(x, y, z) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
        def place(c):
            v = m @ np.array([c[0], c[1], c[2], 1.0])
            return ax.transData.transform([[v[0] / v[3], v[1] / v[3]]])[0], v[3]
        nearest = min(corners, key=lambda c: place(c)[1])
        xy = place(nearest)[0]
        close = np.hypot(points[:, 0] - xy[0], points[:, 1] - xy[1]) < 0.5
        self.assertFalse(close.any(), 'the corner nearest the camera, which no pane draws, is not counted')
        far = max(corners, key=lambda c: place(c)[1])
        xy = place(far)[0]
        self.assertTrue((np.hypot(points[:, 0] - xy[0], points[:, 1] - xy[1]) < 0.5).any(), 'the far corner of the panes is')
        plt.close(figure)

    def test_flat_scene_has_no_offset(self):
        figure = plt.figure()
        figure.add_subplot().plot([0, 1], [0, 1])
        points = cameras.projected_points(figure, figure.canvas.get_renderer())
        self.assertEqual(cameras.fit(points, (10, 4), (640, 480)), {})
        plt.close(figure)


class RenderedPair(unittest.TestCase):
    def test_markers_against_prediction(self):
        figure, ax = scene()
        left, right, offsets = sm.render_pair(figure, (10.0, 4.0))
        b = offsets[ax]
        self.assertGreater(b, 0)
        for name, (p, colour) in MARKERS.items():
            lx, ly, ln = centroid(left, colour)
            rx, ry, rn = centroid(right, colour)
            self.assertGreater(min(ln, rn), 50, name)
            self.assertAlmostEqual(ry - ly, 0.0, delta=0.05, msg='vertical ' + name)
            self.assertAlmostEqual(rx - lx, closed_form(ax, b, depth_of(ax, p)), delta=0.35, msg=name)
        plt.close(figure)

    def test_cameras_restored(self):
        figure, ax = scene()
        sm.render_pair(figure, (10.0, 4.0))
        self.assertNotIn('get_proj', ax.__dict__)
        plt.close(figure)


class Marks(unittest.TestCase):
    def pair(self, w=101, h=40):
        left = np.zeros((h, w, 4), np.uint8); left[..., 0] = 255; left[..., 3] = 255
        right = np.zeros((h, w, 4), np.uint8); right[..., 2] = 255; right[..., 3] = 255
        return left, right

    def test_pns(self):
        left, right = self.pair()
        data = writers.pns_bytes(left, right)
        kinds = [k for k, _ in writers.read_png_chunks(data)]
        self.assertEqual(kinds[:2], [b'IHDR', b'sTER'])
        self.assertLess(kinds.index(b'sTER'), kinds.index(b'IDAT'))
        self.assertEqual(dict(writers.read_png_chunks(data))[b'sTER'], b'\x01')
        width = struct.unpack('>I', data[16:20])[0]
        pad = 7 - ((101 - 1) % 8)
        self.assertEqual(width, 2 * 101 + pad)
        self.assertEqual((101 + pad) % 8, 0, 'the right picture starts on a column divisible by eight')
        picture = np.asarray(Image.open(io.BytesIO(data)).convert('RGBA'))
        self.assertTrue(np.array_equal(picture[:, :101], left))
        self.assertTrue(np.array_equal(picture[:, 101 + pad:], right))
        broken = bytearray(data); broken[40] ^= 1
        with self.assertRaises(ValueError):
            writers.read_png_chunks(bytes(broken))

    def test_jps(self):
        left, right = self.pair(160, 48)
        data = writers.jps_bytes(left, right)
        at = data.find(b'\xff\xe3')
        self.assertGreater(at, 0)
        length = struct.unpack('>H', data[at + 2:at + 4])[0]
        body = data[at + 4:at + 2 + length]
        self.assertTrue(body.startswith(b'_JPSJPS_'), body[:16])
        self.assertEqual(struct.unpack('>H', body[8:10])[0], 4)
        self.assertEqual(struct.unpack('>I', body[10:14])[0], writers.JPS_SIDE_BY_SIDE_RIGHT_FIRST)
        picture = np.asarray(Image.open(io.BytesIO(data)).convert('RGB')).astype(int)
        self.assertGreater(picture[:, :160, 2].mean(), 200, 'stored right eye first')
        self.assertGreater(picture[:, 160:, 0].mean(), 200)

    def test_never_overwrites(self):
        left, right = self.pair()
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, 'mine.pns')
            with open(path, 'wb') as f:
                f.write(b'person')
            with self.assertRaises(writers.StereoFileExists):
                writers.write_pns(path, left, right)
            self.assertEqual(read(path), b'person')
            figure, _ = scene()
            with self.assertRaises(sm.StereoFileExists):
                sm.save_stereo_figure(figure, path)
            self.assertEqual(read(path), b'person')
            sm.save_stereo_figure(figure, os.path.join(folder, 'new.pns'))
            self.assertEqual(sorted(os.listdir(folder)), ['mine.pns', 'new.pns'])
            plt.close(figure)


if __name__ == '__main__':
    unittest.main()
