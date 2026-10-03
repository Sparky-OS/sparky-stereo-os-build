# SPDX-License-Identifier: GPL-2.0-or-later
import json
from pathlib import Path
import paraview.simple as pv
pv._DisableFirstRenderCameraReset()
view = pv.CreateView('RenderView')
view.ViewSize = [640, 360]
view.StereoRender = 1
view.StereoType = 'Crystal Eyes'
view.Background = [0, 0, 0]
view.UseColorPaletteForBackground = 0
view.OrientationAxesVisibility = 0
view.CameraPosition = [0, 0, 0]
view.CameraFocalPoint = [0, 0, -6]
view.CameraViewUp = [0, 1, 0]
view.CameraParallelProjection = 0
centres = []
for depth, y, colour in [(3, .12, [1,0,0]), (6, 0, [0,1,0]), (12, -.12, [0,0,1])]:
    plane = pv.Plane()
    plane.Origin = [-.08*depth, (y-.03)*depth, -depth]
    plane.Point1 = [.08*depth, (y-.03)*depth, -depth]
    plane.Point2 = [-.08*depth, (y+.03)*depth, -depth]
    actor = pv.Show(plane, view)
    actor.AmbientColor = colour
    actor.DiffuseColor = colour
    actor.Ambient = 1
    actor.Diffuse = 0
    centres.append([0, y*depth, -depth, 1])
for i in range(4):
    pv.Render(view)
renderer = view.GetClientSideObject().GetRenderer()
camera = renderer.GetActiveCamera()
assert camera.GetStereo(), 'VTK camera did not enter stereo mode'
# vtkCamera's ordinary stereo path shears by +/- EyeAngle/2 at Distance.
from math import tan, radians
assert not camera.GetUseHorizontalViewAngle()
assert not camera.GetParallelProjection()
convergence = camera.GetDistance()
separation = 2 * convergence * tan(radians(camera.GetEyeAngle()/2))
focal_pixels = 360 / (2 * tan(radians(camera.GetViewAngle()/2)))
expected = [focal_pixels * separation * (1/convergence - 1/(-point[2])) for point in centres]
Path('out/paraview/expected.json').write_text(json.dumps(expected))
print('ParaView camera distance/angle/eye angle:', convergence, camera.GetViewAngle(), camera.GetEyeAngle())
print('ParaView Crystal Eyes expected pixel disparities:', expected)
