# SPDX-License-Identifier: GPL-3.0-only
"""Weather geometry in camera-facing scene units. Positive z is toward the viewer."""
from dataclasses import dataclass, replace
from math import cos, pi, sin, sqrt, tau


@dataclass(frozen=True)
class Shape:
    name: str
    outline: tuple
    rings: tuple
    colour: str
    alpha: float = 1.0
    smooth: bool = False


def radial(radius, points=32):
    return tuple((radius*cos(tau*i/points), radius*sin(tau*i/points)) for i in range(points))


def transform(points, x, y, z, scale_x=1, scale_y=1, angle=0):
    c, s = cos(angle), sin(angle)
    return tuple((x+u*scale_x*c-v*scale_y*s, y+u*scale_x*s+v*scale_y*c, z) for u, v in points)


def prism(name, points, x, y, z, thickness, colour, angle=0, bevel=0.09, alpha=1):
    front = transform(points, x, y, z, 1-bevel, 1-bevel, angle)
    edge = transform(points, x, y, z-thickness*0.16, angle=angle)
    back = transform(points, x, y, z-thickness, 1-bevel, 1-bevel, angle)
    return Shape(name, edge, (front, edge, back), colour, alpha)


def ellipsoid(name, x, y, z, rx, ry, rz, colour, angle=0, alpha=1):
    circle = radial(1, 24)
    rings = []
    for index in range(11):
        latitude = pi*(index/10-0.5)
        radius = max(0.001, cos(latitude))
        rings.append(transform(circle, x, y, z+rz*sin(latitude), rx*radius, ry*radius, angle))
    rings.reverse()
    return Shape(name, rings[5], tuple(rings), colour, alpha, True)


def scaled(shapes, factor, x=0, y=0, z=0):
    def move(ring):
        return tuple((x+factor*a, y+factor*b, z+factor*c) for a,b,c in ring)
    return [replace(shape, outline=move(shape.outline), rings=tuple(map(move, shape.rings))) for shape in shapes]


def turn(points, angle):
    return tuple((x*cos(angle)-y*sin(angle), x*sin(angle)+y*cos(angle)) for x,y in points)


def sun(phase, disc_back):
    disc = prism('solar-disc', radial(.43, 56), 0, 0, 0, disc_back, 'ffad34', bevel=0)
    rays = ((.53,-.071),(.78,-.032),(.87,0),(.78,.032),(.53,.071))
    shapes = [disc, *(prism(f'ray-{i}', turn(rays, tau*(i+phase)/9), 0, 0, .36, .12,
                           'ffcf68', bevel=0) for i in range(9))]
    return [replace(shape,outline=shape.rings[0]) for shape in shapes]


def horizon(phase, disc_back, event):
    """Half a sun on the horizon line and a solid arrow below it, up at sunrise, down at sunset.

    At 22 px the arrow is about six pixels wide, so the two names differ in one colour too.
    """
    rising = event == 'sunrise'
    sun_colour = 'ffb845' if rising else 'ed774d'
    line = -.10
    half = tuple((.40*cos(pi*i/28), line+.40*sin(pi*i/28)) for i in range(29))
    shapes = [prism('solar-disc', half, 0, 0, 0, disc_back, sun_colour, bevel=0)]
    # The rays lengthen and shorten once a loop, the longest in the still.
    reach = .76+.04*cos(tau*phase)
    ray = ((.50,-.06),(reach-.08,-.028),(reach,0),(reach-.08,.028),(.50,.06))
    shapes += [prism(f'ray-{i}', turn(ray, pi*(i+.5)/5), 0, line, .36, .12, sun_colour, bevel=0)
               for i in range(5)]
    shapes.append(prism('horizon', ((-.70,-.04),(.70,-.04),(.70,.04),(-.70,.04)),
                        0, line-.07, -.27, .06, '67748f', bevel=0))
    # A wide head on a thin stem: turned over, the head and the stem trade places, so the silhouette changes.
    arrow = ((0,.28),(.32,-.02),(.08,-.02),(.08,-.28),(-.08,-.28),(-.08,-.02),(-.32,-.02))
    shapes.append(prism('horizon-direction', arrow, 0, line-.455, .15, .08,
                        '79a6ba' if rising else 'a884b5', angle=0 if rising else pi, bevel=0))
    return front(shapes)


def star():
    return tuple((x*(1 if i%2==0 else .36), y*(1 if i%2==0 else .36)) for i,(x,y) in enumerate(radial(1,8)))


def moon(phase):
    outer = [(0.43*cos(pi/2+pi*i/24), .49*sin(pi/2+pi*i/24)) for i in range(25)]
    inner = [(-.31*sin(pi*i/24), -.49*cos(pi*i/24)) for i in range(1,24)]
    crescent = prism('crescent', outer+inner, -.09, -.01, .15, .20, 'f9dda0', angle=-.35, bevel=.055)
    # Bend the solid at both horns. The effect survives a different camera rule.
    def bend(vertices):
        return tuple((x,y,z+.18*(y/.52)**2) for x,y,z in vertices)
    crescent = replace(crescent, outline=bend(crescent.outline), rings=tuple(map(bend,crescent.rings)))
    positions = ((.32,.46,-.40,.108),(.57,.10,-.26,.113),(.32,-.34,-.47,.078),(-.58,.48,-.35,.078))
    stars = [prism(f'star-{i}', tuple((u*r,v*r) for u,v in star()), x,y,z,.055,'dde8ff',
                   alpha=.64+.35*(.5+.5*cos(tau*(phase+i/4)))) for i,(x,y,z,r) in enumerate(positions)]
    return [crescent,*stars]


def cloud(phase, density, darkness, *, x=0, y=0, scale=1, z=0):
    drift = .048*sin(tau*phase)
    puffs = ((-.34,-.03,.02,.27,.20,.16),(-.09,.12,-.06,.33,.28,.20),(.21,.065,.12,.31,.24,.22),
             (.39,-.06,-.04,.24,.17,.18),(-.37,.19,-.33,.26,.20,.13),(.31,.22,-.38,.32,.21,.14),
             (.08,.34,-.46,.32,.21,.13),(-.17,-.18,-.17,.39,.13,.13))
    colour = ('e7eef4','b9c6d8','8797b1','65748e')[darkness]
    shapes = [ellipsoid(f'cloud-{i}', u+drift,v,w,rx,ry,rz,colour)
              for i,(u,v,w,rx,ry,rz) in enumerate(puffs[:density])]
    return scaled(shapes, scale,x,y,z)


def smoothstep(value):
    u = max(0, min(1, value))
    return u*u*(3-2*u)


def flake(name, x, y, z, radius, phase, alpha):
    shapes = []
    for arm in range(3):
        angle = tau*arm/6+tau*phase/6
        shapes.append(ellipsoid(f'{name}-{arm}',x,y,z,radius,.013,.021,'d6ecff',angle,alpha))
        for side in (-1,1):
            a, b = x+side*.60*radius*cos(angle), y+side*.60*radius*sin(angle)
            shapes.append(ellipsoid(f'{name}-{arm}-{side}',a,b,z,radius*.34,.012,.017,'e8f4ff',angle+pi/3,alpha))
    return shapes


def precipitation(phase, density, kinds):
    result = []
    for i in range(density):
        kind = kinds[i%len(kinds)]
        x = (i-(density-1)/2)*min(.24, 1.10/max(1,density-1))
        fall = (phase+(i*5%13)/13+.14)%1
        extent = .67 if kind in ('rain','ice') else .55
        y = .11-extent*fall
        z = (-.43,.12,.49,-.15,.32,-.30,.39)[i%7] + .14*(fall-.5)
        # Smooth gate in and out of the hidden end of the repeating path.
        opacity = smoothstep(fall/.20)*smoothstep((1-fall)/.20)
        tag = f'{kind}-{i}'
        if kind == 'snow':
            result += flake(tag,x+.035*sin(tau*phase),y,z,.082,phase+i*.11,opacity)
        elif kind == 'hail':
            result.append(ellipsoid(tag,x,y,z,.061,.054,.070,'dbe8ef',alpha=opacity))
        else:
            points = ((0,.126),(-.046,-.022),(-.032,-.064),(0,-.073),(.032,-.064),(.046,-.022))
            colour = '9ad8ff' if kind == 'ice' else '55b5ed'
            result.append(prism(tag,points,x,y,z+.045,.095,colour,angle=-.26,alpha=opacity))
    return result


def rain(phase, density):
    return precipitation(phase,density,('rain',))


def snow(phase, density):
    return precipitation(phase,density,('snow',))


def storm(phase):
    points = ((-.09,.25),(.12,.25),(.046,.01),(.18,.02),(-.14,-.42),(-.066,-.12),(-.19,-.13))
    # A baseline remains visible in the still while the second half flashes.
    return [prism('bolt',points,.08,-.17,.59,.11,'ffdc68',bevel=.06,
                  alpha=.20+.80*(.5+.5*cos(tau*phase))**6)]


def fog(phase):
    return [ellipsoid(f'fog-{i}',.14*sin(tau*(phase+i*.2)),.44-.22*i,z,.56,.048,.045,
                      ('c9d7e5','a6bbd0')[i%2],alpha=.85)
            for i,z in enumerate((-.53,-.26,.03,.28,.53))]


def freezing_rain(phase, density):
    return precipitation(phase,density,('rain','ice','hail'))


def hail(phase, density):
    return precipitation(phase,density,('hail','hail','rain'))


def mixed(phase, density):
    return precipitation(phase,density,('rain','snow'))


def ribbon(name, x, y, z, length, colour, phase):
    pts = [(x+length*(i/24-.5),y+.07*sin(tau*(i/24+phase))) for i in range(25)]
    path = [(a,b+.031) for a,b in pts]+[(a,b-.031) for a,b in reversed(pts)]
    return prism(name,path,0,0,z,.06,colour,bevel=.04)


def wind(phase, overlay=False):
    y = -.28 if overlay else .26
    return [ribbon(f'wind-{i}',.09*sin(tau*(phase+i*.2)),y-i*.19,z,.80-i*.14,'6fbacd',phase+i*.18)
            for i,z in enumerate((-.35,.03,.42))]


def status_rim(name, exterior, interior, colour, thickness=.008):
    # Two overlapping open contours form a closed outline without covering its glyph.
    count = len(exterior)
    if count == 3:
        return [prism(f'{name}-{i}', (exterior[i], exterior[(i+1)%count],
                       interior[(i+1)%count], interior[i]), 0, 0, 0, thickness, colour, bevel=0)
                for i in range(count)]
    contours = []
    for start in (0, count//2):
        indices = [(start+i)%count for i in range(-1, count//2+2)]
        points = [exterior[i] for i in indices]+[interior[i] for i in reversed(indices)]
        contours.append(prism(f'{name}-{start}',points,0,0,0,thickness,colour,bevel=0))
    return contours


def front(shapes):
    # The visible contour of a solid seen face on is its front ring.
    return [replace(shape,outline=shape.rings[0]) for shape in shapes]


def status(phase, sign, symbolic=False, disc_back=.008):
    del phase
    if sign == 'alert':
        # The triangle's face is the icon's plane and the mark stands in front of it, at the
        # nearest depth the sun's ray tips have. The triangle's depth puts the camera's
        # convergence on its face, as the sun's disc depth does.
        plate = ((0,.61),(-.65,-.48),(.65,-.48))
        rim = status_rim('warning',plate,((0,.39),(-.48,-.37),(.48,-.37)),'e7a248',disc_back) if symbolic else [
            prism('warning',plate,0,0,0,disc_back,'e7a248',bevel=0)]
        return front([*rim,
                      prism('stroke',((-.042,-.16),(.042,-.16),(.062,.25),(-.062,.25)),0,0,.36,.12,'372515',bevel=0),
                      prism('dot',radial(.047),0,-.275,.36,.12,'372515',bevel=0)])
    plate = radial(.58)
    rim = status_rim('status',plate,radial(.46),'91abc1') if symbolic else [
        prism('status',plate,0,0,0,.008,'91abc1',bevel=0)]
    if sign == 'humidity':
        mark = ((0,.33),(-.22,-.10),(-.16,-.26),(0,-.34),(.16,-.26),(.22,-.10))
    elif sign == 'pressure':
        mark = ((-.20,-.18),(-.09,-.24),(.28,.28),(.13,.23))
    else:
        mark = ((-.29,-.053),(.29,-.053),(.29,.053),(-.29,.053))
    return [*rim,prism('status-glyph',mark,0,0,.0002,.002,'203447',bevel=0)]


def _parameters(name):
    key = name.removeprefix('weather-').removesuffix('-symbolic')
    night = 'night' in key
    timed = 'day' in key or night
    windy = 'wind' in key
    if key in ('severe-alert','none-available','pressure','humidity'):
        return dict(family='status', sign='alert' if key=='severe-alert' else key)
    if key.startswith('clear') or key in ('sunrise','sunset'):
        return dict(family='moon' if night else 'sun', windy=windy, horizon=key if key in ('sunrise','sunset') else None, inset=.86 if key=='clear' else 1)
    if key in ('fog','mist'):
        return dict(family='fog')
    if key == 'windy':
        return dict(family='wind')
    if 'storm' in key:
        family = 'storm'
    elif 'freezing' in key:
        family = 'freezing-rain'
    elif 'hail' in key:
        family = 'hail'
    elif 'snow-rain' in key:
        family = 'mixed'
    elif 'snow' in key:
        family = 'snow'
    elif 'showers' in key or 'rain' in key:
        family = 'rain'
    else:
        family = 'cloud'
    if family == 'cloud':
        density = 4 if 'few' in key else 8 if 'overcast' in key else 7 if 'many' in key else 5
        darkness = 3 if 'overcast' in key else 2 if 'many' in key or night else 1 if density>4 else 0
        luminary = ('moon' if night else 'sun') if timed or 'few' in key else None
    else:
        density = 4 if 'scattered' in key else 9 if 'heavy' in key else 7 if family in ('rain','snow') else 5
        darkness = 3 if family == 'storm' else 2 if night else 1
        luminary = ('moon' if night else 'sun') if timed else None
    return dict(family=family,density=density,darkness=darkness,luminary=luminary,windy=windy,
                storm_precip=('snow' if 'snow' in key else 'ice' if 'freezing' in key else 'rain'))


def _model(params, phase, disc_back):
    phase %= 1
    family = params['family']
    if family == 'sun' and params.get('horizon'):
        return horizon(phase,disc_back,params['horizon'])
    if family in ('sun','moon'):
        shapes = sun(phase,disc_back) if family=='sun' else moon(phase)
        if params.get('inset',1)<1:
            factor=params['inset']
            def inset(ring):
                return tuple((x*factor,y*factor,z) for x,y,z in ring)
            shapes=[replace(shape,outline=inset(shape.outline),rings=tuple(map(inset,shape.rings))) for shape in shapes]
        if params.get('windy'):
            shapes = scaled(shapes,.70,y=.16)
            shapes += wind(phase, overlay=True)
        return shapes
    if family == 'status':
        return status(phase,params['sign'],params.get('symbolic',False),disc_back)
    if family in ('fog','wind'):
        return fog(phase) if family=='fog' else wind(phase)
    if family == 'cloud':
        shapes = cloud(phase,params['density'],params['darkness'],y=-.10 if params['luminary'] else -.05)
        if params['windy']:
            shapes += wind(phase,overlay=True)
    else:
        shapes = cloud(phase,5,params['darkness'],y=.37,scale=.89,z=-.10)
        density = params['density']
        if family == 'storm':
            shapes += storm(phase)+precipitation(phase,4,(params['storm_precip'],))
        else:
            emitter = {'rain':rain,'snow':snow,'freezing-rain':freezing_rain,'hail':hail,'mixed':mixed}[family]
            shapes += emitter(phase,density)
    if params['luminary']:
        light = moon(phase) if params['luminary']=='moon' else sun(phase,disc_back)
        shapes += scaled(light,.52,x=-.38,y=.45 if family=='cloud' else .43,z=-.34)
    return shapes


def parameters(name):
    settings = _parameters(name)
    if name.endswith('-symbolic'):
        settings['symbolic'] = True
    return settings


def model(params, phase, disc_back):
    shapes = _model(params, phase, disc_back)
    if params.get('symbolic'):
        return [replace(shape,colour='e6e7e8') for shape in shapes]
    if params.get('contrast'):
        colours = {'crescent':'bf8a46','star':'819ac0','snow-':'7295bc'}
        return [replace(shape,colour=next((colour for prefix,colour in colours.items()
                                          if shape.name.startswith(prefix)),shape.colour))
                for shape in shapes]
    return shapes
