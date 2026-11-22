"""pv_shot.py OUT: an old screenshot stereo mode met by the edition ParaView (pvpython), four ways: from the user settings
(misc.SaveScreenshot.StereoMode 7, Anaglyph's value), the integer 7, the old string 'Anaglyph', and the kept 'Both Eyes'."""
import sys
from paraview.simple import GetActiveViewOrCreate, Render, SaveScreenshot, Show, Sphere

out = sys.argv[1]
Show(Sphere())
view = GetActiveViewOrCreate('RenderView')
Render(view)
for name, kw in (('from-settings', {}), ('int-7', {'StereoMode': 7}), ('string-anaglyph', {'StereoMode': 'Anaglyph'}),
                 ('both-eyes', {'StereoMode': 'Both Eyes'})):
    try:
        SaveScreenshot('%s/%s.png' % (out, name), view, ImageResolution=[400, 300], **kw)
        print(name, 'saved', flush=True)
    except Exception as error:
        print(name, 'failed:', type(error).__name__, error, flush=True)
