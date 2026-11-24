# SPDX-License-Identifier: GPL-3.0-only
"""Sparky Stereo Real Weather as data: what stands where at a phase, built on the modelled geometry.

The realistic look keeps each family's depth structure: every real element is placed from the modelled
solid it replaces, so the cameras the modelled look calibrates serve this look unchanged.
No Blender here: the renderer and the checks both import it.
"""
from math import atan2, cos, hypot, pi, radians, sin, sqrt, tau

import geometry as geo

LOOK = 'Sparky Stereo Real Weather'
SUN_RADIUS = .43
# The sun's centre is the icon's plane. Its pole stands at this fraction of the rays' reach toward the
# viewer, so the streamers' tips stay the nearest element, as the modelled rays' tips are.
SUN_POLE = .8
SUN_RAY_FRONT = .36
SUN_TURN = radians(4)
CORONA_REACH = 1.45
CORONA_DEPTH = .14
STREAMER_RADII = (.052, .012)
MOON_RADIUS = .46
MOON_CENTRE = (-.09, -.01)
# The light falls from behind the Moon on its upper left, as the modelled crescent is lit: a crescent of
# about 21 % of the disc (phase angle 125 degrees), the horns turned as the modelled crescent's (-0.35 rad).
MOON_PHASE_ANGLE = radians(125)
MOON_TILT = -.35
CLOUD_LOOP_RADIUS = .35
LIGHT = dict(sun=dict(direction=(-.25, .95, -.15), strength=14., colour='fff1dc', angle=8, receives=('cloud', 'fog')),
             moon=dict(strength=18., colour='f1f3ff', angle=1, receives=('moon',)),
             moonlight=dict(direction=(-.40, .80, -.30), strength=1.6, colour='cdd6ff', angle=4, receives=('cloud', 'fog')),
             sky=dict(direction=(.10, 1., .30), strength=7., colour='f4f8ff', angle=40, receives=('cloud', 'fog')))
REPLACED = ('solar-disc', 'ray-', 'crescent', 'cloud-', 'bolt', 'fog-', 'aurora-0-', 'aurora-1-', 'aurora-2-')


def normalized(vector):
    length = sqrt(sum(v*v for v in vector))
    return tuple(v/length for v in vector)


def moon_light():
    x, y = cos(pi+MOON_TILT), sin(pi+MOON_TILT)
    return normalized((sin(MOON_PHASE_ANGLE)*x, sin(MOON_PHASE_ANGLE)*y, cos(MOON_PHASE_ANGLE)))


def points(shape):
    return [point for ring in shape.rings for point in ring]


def bbox(shape):
    pts = points(shape)
    return [(min(p[i] for p in pts), max(p[i] for p in pts)) for i in range(3)]


def axis_map(canonical, placed):
    """Per-axis scale and offset that take a canonical solid to its place in the composition."""
    result = []
    for (a0, a1), (b0, b1) in zip(bbox(canonical), bbox(placed)):
        scale = (b1-b0)/(a1-a0) if a1-a0 > 1e-12 else 1.
        result.append((scale, b0-scale*a0))
    return result


def mapped(axes, point):
    return tuple(s*v+o for (s, o), v in zip(axes, point))


def replaced(name):
    return name.startswith(REPLACED)


def sun_specs(params, by, phase, disc_back, streamers=True):
    horizon = params.get('horizon')
    if horizon:
        canonical = next(s for s in geo.horizon(0, disc_back, horizon) if s.name == 'solar-disc')
        centre, radius, clip = (0, -.10, 0), .40, -.10
    else:
        canonical = next(s for s in geo.sun(0, disc_back) if s.name == 'solar-disc')
        centre, radius, clip = (0, 0, 0), SUN_RADIUS, None
    axes = axis_map(canonical, by['solar-disc'])
    (sx, _), (sy, _), (sz, _) = axes
    middle = mapped(axes, centre)
    radii = (radius*sx, radius*sy, SUN_POLE*SUN_RAY_FRONT*sz)
    clip_local = None if clip is None else 0.
    specs = [dict(kind='sun', name='sun', centre=middle, radii=radii, clip=clip_local,
                  turn=(SUN_TURN*phase, SUN_TURN*(phase-1)), mix=phase,
                  z=(middle[2], middle[2]+radii[2])),
             dict(kind='corona', name='corona', centre=middle,
                  radii=(CORONA_REACH*radii[0], CORONA_REACH*radii[1], CORONA_DEPTH*sz), clip=clip_local,
                  breath=1+.18*sin(tau*phase), z=(middle[2]-CORONA_DEPTH*sz, middle[2]+CORONA_DEPTH*sz))]
    if not streamers:
        return specs
    for shape in by.values():
        if not shape.name.startswith('ray-'):
            continue
        front = shape.rings[0]
        tip = max(front, key=lambda p: hypot(p[0]-middle[0], p[1]-middle[1]))
        angle = atan2(tip[1]-middle[1], tip[0]-middle[0])
        start = (middle[0]+radii[0]*cos(angle), middle[1]+radii[1]*sin(angle), middle[2])
        specs.append(dict(kind='streamer', name=shape.name.replace('ray-', 'streamer-'), start=start,
                          end=tuple(tip), radii=(STREAMER_RADII[0]*sx, STREAMER_RADII[1]*sx),
                          z=(start[2], tip[2])))
    return specs


def moon_spec(params, by):
    canonical = next(s for s in geo.moon(0) if s.name == 'crescent')
    axes = axis_map(canonical, by['crescent'])
    front = bbox(canonical)[2][1]
    centre = mapped(axes, (*MOON_CENTRE, front-MOON_RADIUS))
    radii = tuple(MOON_RADIUS*s for s, _ in axes)
    return dict(kind='moon', name='moon', centre=centre, radii=radii, light=moon_light(),
                hemisphere=params.get('hemisphere', 'north'), z=(centre[2], centre[2]+radii[2]))


def ellipsoid_spec(kind, shape, phase, index):
    (x0, x1), (y0, y1), (z0, z1) = bbox(shape)
    return dict(kind=kind, name=shape.name, centre=((x0+x1)/2, (y0+y1)/2, (z0+z1)/2),
                radii=((x1-x0)/2, (y1-y0)/2, (z1-z0)/2), colour=shape.colour, seed=index,
                loop=(CLOUD_LOOP_RADIUS*cos(tau*phase), CLOUD_LOOP_RADIUS*sin(tau*phase)), z=(z0, z1))


def jagged(start, end, count, amplitude, offsets):
    """A channel from start to end in count steps, jittered across its direction in x and y only."""
    dx, dy = end[0]-start[0], end[1]-start[1]
    length = hypot(dx, dy) or 1
    nx, ny = -dy/length, dx/length
    result = []
    for i in range(count+1):
        t = i/count
        jitter = 0 if i in (0, count) else amplitude*offsets[i % len(offsets)]
        result.append((start[0]+dx*t+nx*jitter, start[1]+dy*t+ny*jitter, start[2]+(end[2]-start[2])*t))
    return result


# Fixed offsets, so every run draws the same channel.
OFFSETS = (.0, .9, -.7, .4, -1., .6, -.3, .8, -.5, .2, -.9, .7)
# Frame by frame: the flash, its afterglow in the cloud, the dark, then the leader stepping down.
BOLT_SCHEDULE = [(1., 1., 1.), (.55, 1., .55), (.22, 1., .25)]+[(0., 0., 0.)]*5+[
    (.22, f, .05) for f in (.25, .45, .65, .85)]


def bolt_spec(by, phase):
    (x0, x1), (y0, y1), (z0, z1) = bbox(by['bolt'])
    middle = (x0+x1)/2
    main = jagged((middle+.03, y1+.06, .18), (middle-.05, y0-.02, .40), 11, .045, OFFSETS)
    near = jagged(main[4], (middle+.20, y0+.14, z1), 6, .03, OFFSETS[3:])
    twig = jagged(near[2], (middle+.28, y0+.31, .50), 3, .02, OFFSETS[5:])
    far = jagged(main[3], (middle-.21, y0+.25, -.22), 6, .03, OFFSETS[1:])
    frame = round(phase*12) % 12
    glow, reach, cloud = BOLT_SCHEDULE[frame]
    return dict(kind='bolt', name='bolt', main=main, near=near, twig=twig, far=far, frame=frame,
                glow=glow, reach=reach, cloud=cloud, light=(middle, y1+.14, -.04),
                z=(min(p[2] for p in far), z1),
                features={'bolt-near': (main[4][2], z1), 'bolt-far': (far[-1][2], main[3][2])})


def aurora_specs(phase):
    specs = []
    for k, (z, height, offset) in enumerate(geo.AURORA_CURTAINS):
        base = [geo.aurora_base(k, phase, i/80) for i in range(81)]
        specs.append(dict(kind='aurora', name=f'aurora-{k}', base=[(x, y) for x, y, _, _ in base], depth=z,
                          height=height, phase=phase, offset=offset, z=(z, z)))
    return specs


def lamp_specs(params):
    """The luminary's light: the Moon's phase from one lamp, the clouds lit by the luminary of the name."""
    family = params['family']
    if family in ('status', 'wind', 'aurora'):
        return []
    luminary = params.get('luminary') or {'sun': 'sun', 'moon': 'moon'}.get(family)
    if luminary == 'moon':
        return [dict(kind='lamp', name='moon-light', direction=moon_light(), **LIGHT['moon']),
                dict(kind='lamp', name='moonlight', **LIGHT['moonlight'])]
    return [dict(kind='lamp', name=f'{luminary or "sky"}-light', **LIGHT[luminary or 'sky'])]


def specs(params, shapes, phase, disc_back):
    """The real scene at phase: luminaries, volumes, the bolt and the curtains, and the solids kept as modelled."""
    phase %= 1
    by = {shape.name: shape for shape in shapes}
    result = []
    result += lamp_specs(params)
    if 'solar-disc' in by:
        result += sun_specs(params, by, phase, disc_back, params.get('streamers', True))
    if 'crescent' in by:
        result.append(moon_spec(params, by))
    clouds = [shape for shape in shapes if shape.name.startswith('cloud-')]
    result += [ellipsoid_spec('cloud', shape, phase, i) for i, shape in enumerate(clouds)]
    fog = [shape for shape in shapes if shape.name.startswith('fog-')]
    result += [ellipsoid_spec('fog', shape, phase, i) for i, shape in enumerate(fog)]
    if 'bolt' in by:
        result.append(bolt_spec(by, phase))
    if params['family'] == 'aurora':
        result += aurora_specs(phase)
    result += [dict(kind='solid', name=shape.name, z=tuple(bbox(shape)[2])) for shape in shapes
               if not replaced(shape.name)]
    return result


def signature(scene):
    """What a phase's scene is, rounded, to compare the pose after the wrap with phase 0."""
    def clean(value):
        if isinstance(value, float):
            return round(value, 9)+0.
        if isinstance(value, (list, tuple)):
            return [clean(v) for v in value]
        if isinstance(value, dict):
            return {k: clean(v) for k, v in value.items()}
        return value
    return clean(scene)


def counterpart(name, scene):
    """The real element that stands for a modelled feature, for the depth checks."""
    names = {spec['name'] for spec in scene}
    if name == 'solar-disc':
        return 'sun'
    if name.startswith('ray-'):
        return name.replace('ray-', 'streamer-') if name.replace('ray-', 'streamer-') in names else 'sun'
    if name == 'crescent':
        return 'moon'
    if name.startswith('aurora-') and name.count('-') >= 2 and name.split('-')[1].isdigit():
        return 'aurora-'+name.split('-')[1]
    return name
