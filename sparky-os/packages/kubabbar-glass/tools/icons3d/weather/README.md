# Weather icon models

The model takes a theme name and a phase from 0 to 1.
`geometry.py` supplies solids in camera-facing scene units, with positive z toward the viewer.
Each solid carries its contour, closed mesh, colour and opacity.
The vector export projects that contour. Blender shades the mesh from the same geometry.

The families are sun, moon, cloud, rain, snow, storm, fog, freezing rain, hail, mixed precipitation, wind and flat status signs.
`parameters()` maps variant names to density, darkness, luminary, precipitation and wind.
A crescent's thickness and bent horns, a star's depth, and a particle's path stay in the geometry when the camera calibration changes.

Run inside Blender with NumPy available.

```bash
blender -b --threads 4 --python-exit-code 1 --python weather/render.py -- OUT SCRATCH weather-clear weather-clear-night
```

The renderer uses the parallel rig and separation solver in `../scene.py`, calibrating one camera pair at each raster size across the whole loop.
It removes the studio floor and writes transparent, left-first 16-bit RGBA PNG pairs at the theme sizes.
The standard `sTER` padding goes between the images.
Loop PNGs in the scratch folder carry complete left and right views for the JPEG XL encoder.
`geometry.json` records the sizes, camera projection, scene extents, named edge features, and the loop's endpoint comparison.
Use `--sizes 64 --static-only` to regenerate the 64 px master. The same geometry and per-size camera give the same picture.

There are twelve 100 ms poses. Phase 0 is the authored still. Advance an additional interval from phase 11 and compare the resulting geometry and opacity with phase 0.
Precipitation takes the fade to zero before it resets on the next cycle. The sun completes one interval of its ninefold symmetry. The status signs use a stationary timeline.

The aurora (`weather-aurora`, an addition of ours: no freedesktop name exists) is curtains of light at three depths over a dark horizon, stars behind them; the light runs along each curtain once a loop.

## Sparky Stereo Real Weather

The third look renders the same names with real spheres and volumes: `real_model.py` describes each phase's scene as data, placed from the modelled solids it replaces, and `real.py` builds it in Blender through the same cameras, so one calibration and one check serve the three looks.
The Moon carries NASA's Scientific Visualization Studio's CGI Moon Kit (the LROC colour map and LOLA relief at true scale), its phase from one light behind it; the Sun a STEREO Ahead SECCHI EUVI 304 Å disc in false colour, a breathing corona and nine streamers; clouds and fog are volumes; the bolt is a forked channel in depth; drops, flakes, hail, wind and the signs are the modelled solids.
`real_sources.py` derives the textures from the downloaded files and records their checksums; the renderer reads them from `REAL_WEATHER_SOURCES`.

```bash
blender -b --python-exit-code 1 --python weather/real_sources.py -- DOWNLOADS SOURCES
REAL_WEATHER_SOURCES=SOURCES blender -b --threads 4 --python-exit-code 1 --python weather/real.py -- OUT SCRATCH weather-clear
```

The renderer refuses a name whose real elements leave the modelled depth range, or whose scene after the wrap differs from phase 0.
`REAL_WEATHER_HEMISPHERE=south` turns the Moon's face for the southern hemisphere; the default is north.
