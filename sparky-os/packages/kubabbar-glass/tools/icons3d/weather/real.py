# SPDX-License-Identifier: GPL-3.0-only
"""Render Sparky Stereo Real Weather: real spheres with NASA's Moon and a STEREO Sun, volumetric clouds,
a forked bolt and aurora curtains, through the cameras the modelled look calibrates. Run inside Blender.

blender -b --threads 4 --python-exit-code 1 --python weather/real.py -- OUT SCRATCH NAME... [options]
"""
import argparse
import json
import math
import os
from pathlib import Path
import resource
import shutil
import sys
import time

import bpy
from mathutils import Matrix, Vector
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import render as base
import geometry as geo
import real_model as rm
from picture import write_png

studio = base.studio
SOURCES = Path(os.environ.get('REAL_WEATHER_SOURCES', '/evidence/models/real-weather/sources'))
STUDIO_LIGHTS = ('key', 'strip-right', 'rim')
CACHE = {}
SOLIDS = {}


def linear(hex_colour):
    return tuple(base.linear(int(hex_colour[i:i+2], 16)/255) for i in (0, 2, 4))


class Graph:
    """A material's node tree with small helpers for maths on sockets and constants."""

    def __init__(self, name):
        self.material = bpy.data.materials.new(name)
        self.material.use_nodes = True
        self.tree = self.material.node_tree
        for node in list(self.tree.nodes):
            self.tree.nodes.remove(node)
        self.output = self.node('ShaderNodeOutputMaterial')

    def node(self, kind, **settings):
        node = self.tree.nodes.new(kind)
        for key, value in settings.items():
            setattr(node, key, value)
        return node

    def put(self, socket, value):
        if isinstance(value, bpy.types.NodeSocket):
            self.tree.links.new(value, socket)
        else:
            if isinstance(value, tuple) and len(value) == 3 and len(socket.default_value) == 4:
                value = (*value, 1.)
            socket.default_value = value

    def math(self, operation, a, b=0., clamp=False):
        node = self.node('ShaderNodeMath', operation=operation, use_clamp=clamp)
        self.put(node.inputs[0], a)
        self.put(node.inputs[1], b)
        return node.outputs[0]

    def smooth(self, value, low, high):
        node = self.node('ShaderNodeMapRange', interpolation_type='SMOOTHSTEP')
        self.put(node.inputs['Value'], value)
        node.inputs['From Min'].default_value = low
        node.inputs['From Max'].default_value = high
        return node.outputs['Result']

    def vector(self, operation, a, b=None, scale=None):
        node = self.node('ShaderNodeVectorMath', operation=operation)
        self.put(node.inputs[0], a)
        if b is not None:
            self.put(node.inputs[1], b)
        if scale is not None:
            self.put(node.inputs['Scale'], scale)
        return node.outputs['Value' if operation in ('DOT_PRODUCT', 'LENGTH') else 'Vector']

    def xyz(self, vector):
        node = self.node('ShaderNodeSeparateXYZ')
        self.put(node.inputs[0], vector)
        return node.outputs

    def combine(self, x, y, z=0.):
        node = self.node('ShaderNodeCombineXYZ')
        for socket, value in zip(node.inputs, (x, y, z)):
            self.put(socket, value)
        return node.outputs[0]

    def colour_mix(self, a, b, factor):
        return self.vector('ADD', a, self.vector('SCALE', self.vector('SUBTRACT', b, a), scale=factor))

    def coordinates(self, kind='Object'):
        return self.node('ShaderNodeTexCoord').outputs[kind]

    def emission(self, colour, strength=1.):
        node = self.node('ShaderNodeEmission')
        self.put(node.inputs['Color'], colour)
        self.put(node.inputs['Strength'], strength)
        return node.outputs[0]

    def cover(self, shader, alpha):
        """The shader where alpha is 1, nothing where it is 0: a soft edge that stays transparent outside."""
        mix = self.node('ShaderNodeMixShader')
        self.put(mix.inputs[0], alpha)
        self.tree.links.new(self.node('ShaderNodeBsdfTransparent').outputs[0], mix.inputs[1])
        self.tree.links.new(shader, mix.inputs[2])
        return mix.outputs[0]

    def surface(self, shader):
        self.tree.links.new(shader, self.output.inputs['Surface'])
        return self.material

    def volume(self, shader):
        self.tree.links.new(shader, self.output.inputs['Volume'])
        return self.material


def image(name, colourspace='sRGB'):
    if name not in CACHE:
        picture = bpy.data.images.load(str(SOURCES/name))
        picture.colorspace_settings.name = colourspace
        CACHE[name] = picture
    return CACHE[name]


def grid(name, lon, lat, radius=None):
    """A latitude and longitude grid on a sphere, x to the right, y up and z toward the viewer."""
    L, P = np.meshgrid(lon, lat)
    r = 1. if radius is None else radius
    co = np.stack((r*np.cos(P)*np.sin(L), r*np.sin(P), r*np.cos(P)*np.cos(L)), -1).reshape(-1, 3)
    rows, cols = P.shape
    first = (np.arange(rows-1)[:, None]*cols+np.arange(cols-1)[None, :]).ravel()
    quads = np.stack((first, first+1, first+1+cols, first+cols), -1)
    mesh = bpy.data.meshes.new(name)
    mesh.vertices.add(len(co))
    mesh.vertices.foreach_set('co', co.astype(np.float32).ravel())
    mesh.loops.add(quads.size)
    mesh.loops.foreach_set('vertex_index', quads.astype(np.int32).ravel())
    mesh.polygons.add(len(quads))
    mesh.polygons.foreach_set('loop_start', np.arange(0, quads.size, 4, dtype=np.int32))
    mesh.polygons.foreach_set('loop_total', np.full(len(quads), 4, dtype=np.int32))
    uv = np.stack(((L.ravel()+math.pi)/(2*math.pi), (P.ravel()+math.pi/2)/math.pi), -1)
    layer = mesh.uv_layers.new(name='UVMap')
    layer.data.foreach_set('uv', uv[quads.ravel()].astype(np.float32).ravel())
    mesh.update()
    mesh.validate()
    mesh.shade_smooth()
    mesh['keep'] = True
    return mesh


def unit_sphere():
    if 'sphere' not in CACHE:
        CACHE['sphere'] = grid('rw-unit-sphere', np.linspace(-math.pi, math.pi, 97),
                               np.linspace(-math.pi/2, math.pi/2, 49))
    return CACHE['sphere']


def moon_mesh():
    """The visible half of the Moon and a margin, relief at its true scale from LOLA (km over 1737.4 km)."""
    if 'moon' not in CACHE:
        heights = np.frombuffer((SOURCES/'moon-height-1440x720-km.f32').read_bytes(), '<f4').reshape(720, 1440)
        lat = np.radians(90-(np.arange(720)+.5)*.25)[::-1]
        lon_deg = -180+(np.arange(1440)+.5)*.25
        keep = np.abs(lon_deg) <= 95
        radius = 1+heights[::-1][:, keep]/1737.4
        CACHE['moon'] = grid('rw-moon', np.radians(lon_deg[keep]), lat, radius)
    return CACHE['moon']


def collection():
    if 'rw' not in bpy.data.collections:
        bpy.context.scene.collection.children.link(bpy.data.collections.new('rw'))
    return bpy.data.collections['rw']


def clear():
    for obj in list(collection().objects):
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and data.users == 0 and not data.get('keep'):
            for store in (bpy.data.meshes, bpy.data.curves, bpy.data.lights):
                if data.name in store and store[data.name] == data:
                    store.remove(data)
                    break
    for material in list(bpy.data.materials):
        if material.name.startswith('rw-') and material.users == 0:
            bpy.data.materials.remove(material)


def assign(obj, material):
    """A material on the object's own slot: the cached spheres are shared by many objects."""
    if not obj.material_slots:
        obj.data.materials.append(None)
    slot = obj.material_slots[0]
    slot.link = 'OBJECT'
    slot.material = material


def add(name, data, matrix=Matrix()):
    obj = bpy.data.objects.new(name, data)
    collection().objects.link(obj)
    obj.matrix_world = WORLD[0] @ matrix
    return obj


def ellipsoid_matrix(spec, rotation=Matrix()):
    scale = Matrix.Diagonal((*spec['radii'], 1))
    return Matrix.Translation(spec['centre']) @ rotation @ scale


def sun_material(spec, record):
    g = Graph('rw-sun')
    local = g.coordinates()
    k = record['sun']['limb_radius']/(record['sun']['crop'][2]/2)
    colours = []
    for angle in spec['turn']:
        rotate = g.node('ShaderNodeVectorRotate', rotation_type='Y_AXIS')
        g.put(rotate.inputs['Vector'], local)
        rotate.inputs['Angle'].default_value = angle
        x, y, _ = g.xyz(rotate.outputs[0])
        u = g.math('ADD', g.math('MULTIPLY', x, .5*k), .5)
        v = g.math('ADD', g.math('MULTIPLY', y, .5*k), .5)
        texture = g.node('ShaderNodeTexImage', image=image('sun-304-disc.png'), extension='EXTEND',
                         interpolation='Cubic')
        g.put(texture.inputs['Vector'], g.combine(u, v))
        colours.append(texture.outputs['Color'])
    glow = g.emission(g.colour_mix(colours[0], colours[1], spec['mix']), 1.)
    if spec['clip'] is not None:
        _, y, _ = g.xyz(local)
        glow = g.cover(glow, g.math('GREATER_THAN', y, spec['clip']))
    return g.surface(glow)


def corona_material(spec):
    g = Graph('rw-corona')
    local = g.coordinates()
    x, y, z = g.xyz(local)
    rho = g.math('MULTIPLY', g.vector('LENGTH', g.combine(x, y)), rm.CORONA_REACH)
    rise = g.smooth(rho, .97, 1.03)
    fall = g.math('POWER', g.math('SUBTRACT', 1., g.smooth(rho, 1.03, rm.CORONA_REACH)), 2.)
    thin = g.math('SUBTRACT', 1., g.math('MULTIPLY', z, z), clamp=True)
    field = g.math('MULTIPLY', g.math('MULTIPLY', rise, fall), g.math('MULTIPLY', thin, spec['breath']))
    if spec['clip'] is not None:
        field = g.math('MULTIPLY', field, g.math('GREATER_THAN', y, spec['clip']/rm.CORONA_REACH))
    volume = g.node('ShaderNodeVolumePrincipled')
    # Absorption and emission only: scattering would pick up the studio world's cool tint.
    volume.inputs['Color'].default_value = (0., 0., 0., 1.)
    volume.inputs['Absorption Color'].default_value = (0., 0., 0., 1.)
    g.put(volume.inputs['Density'], g.math('MULTIPLY', field, 7.))
    volume.inputs['Emission Color'].default_value = (*linear('ffb03c'), 1)
    g.put(volume.inputs['Emission Strength'], g.math('MULTIPLY', field, 9.))
    return g.volume(volume.outputs[0])


def tube_mesh(name, start, end, radii, around=12, along=24):
    s, e = Vector(start), Vector(end)
    axis = (e-s).normalized()
    side = axis.orthogonal().normalized()
    other = axis.cross(side)
    co, uv = [], []
    for i in range(along+1):
        t = i/along
        centre = s.lerp(e, t)
        r = radii[0]+(radii[1]-radii[0])*t
        for j in range(around):
            a = 2*math.pi*j/around
            co.append(centre+r*(math.cos(a)*side+math.sin(a)*other))
            uv.append((t, j/around))
    faces = [(i*around+j, i*around+(j+1) % around, (i+1)*around+(j+1) % around, (i+1)*around+j)
             for i in range(along) for j in range(around)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(c) for c in co], [], faces)
    layer = mesh.uv_layers.new(name='UVMap')
    for poly in mesh.polygons:
        for loop in poly.loop_indices:
            layer.data[loop].uv = uv[mesh.loops[loop].vertex_index]
    mesh.shade_smooth()
    return mesh


def streamer_material():
    if 'rw-streamer' in bpy.data.materials:
        return bpy.data.materials['rw-streamer']
    g = Graph('rw-streamer')
    t, _, _ = g.xyz(g.coordinates('UV'))
    alpha = g.math('MULTIPLY', g.math('SUBTRACT', 1., g.smooth(t, .78, 1.)), .88)
    colour = g.colour_mix(linear('ffd56e'), linear('fff2c4'), g.smooth(t, .2, 1.))
    material = g.surface(g.cover(g.emission(colour, 1.), alpha))
    material.use_fake_user = True
    return material


def moon_material(spec):
    g = Graph('rw-moon')
    texture = g.node('ShaderNodeTexImage', image=image('moon-colour-1024x512.png'), interpolation='Cubic')
    g.put(texture.inputs['Vector'], g.coordinates('UV'))
    diffuse = g.node('ShaderNodeBsdfDiffuse')
    g.put(diffuse.inputs['Color'], texture.outputs['Color'])
    diffuse.inputs['Roughness'].default_value = 1.
    light = WORLD[1] @ Vector(spec['light'])
    geometry = g.node('ShaderNodeNewGeometry')
    facing = g.vector('DOT_PRODUCT', geometry.outputs['Normal'], tuple(light))
    # A ray through the transparent dark side meets the inside of the far rim: that face is not the Moon's.
    front = g.math('SUBTRACT', 1., geometry.outputs['Backfacing'])
    return g.surface(g.cover(diffuse.outputs[0], g.math('MULTIPLY', g.smooth(facing, -.03, .12), front)))


def volume_material(spec):
    """Billowing cloud or fog: noise drawn along a closed circle per loop, thinning to nothing at the solid's edge."""
    g = Graph(f'rw-{spec["kind"]}')
    local = g.coordinates()
    distance = g.vector('LENGTH', local)
    if spec['kind'] == 'fog':
        stretched = g.vector('MULTIPLY', local, (.35, 2.2, 1.6))
        scale, anisotropy, rough = 2.6, .15, (spec['core'], 1., .0)
    else:
        stretched = local
        scale, anisotropy, rough = 1.9, .2, (spec['core'], .90, .32)
    seed = spec['seed']
    shift = (1.7*seed+spec['loop'][0], 2.3*seed+spec['loop'][1], .9*seed)
    noise = g.node('ShaderNodeTexNoise', noise_dimensions='3D')
    g.put(noise.inputs['Vector'], g.vector('ADD', stretched, shift))
    noise.inputs['Scale'].default_value = scale
    noise.inputs['Detail'].default_value = 2.5
    noise.inputs['Roughness'].default_value = .55
    # The noise moves the surface of each puff in and out (a cauliflower outline for a cloud, a soft band for
    # fog); the last factor brings the density to nothing at the solid's own edge, so the tile's border stays clear.
    wobble = g.math('ADD', distance, g.math('MULTIPLY', g.math('SUBTRACT', noise.outputs['Fac'], .5), rough[2]))
    body = g.math('SUBTRACT', 1., g.smooth(wobble, rough[0], rough[1]))
    hull = g.math('SUBTRACT', 1., g.smooth(distance, .86, 1.))
    inner = g.math('ADD', .45, g.math('MULTIPLY', g.smooth(noise.outputs['Fac'], .30, .64), .55))
    field = g.math('MULTIPLY', g.math('MULTIPLY', body, hull), inner)
    volume = g.node('ShaderNodeVolumePrincipled')
    # The scattering colour and the density come with the scene (real_model.ellipsoid_spec).
    volume.inputs['Color'].default_value = (*spec['albedo'], 1)
    volume.inputs['Anisotropy'].default_value = anisotropy
    size_factor = g.node('ShaderNodeValue', name='rw-size')
    size_factor.outputs[0].default_value = 1.
    g.put(volume.inputs['Density'], g.math('MULTIPLY', g.math('MULTIPLY', field, spec['density']),
                                           size_factor.outputs[0]))
    g.material['small'] = spec['small']
    return g.volume(volume.outputs[0])


def size_materials(size):
    """A volume's density at the panel's sizes: its small factor at rm.SMALL_SIZE px and below, 1 above."""
    for material in bpy.data.materials:
        node = material.node_tree.nodes.get('rw-size') if material.node_tree else None
        if node is not None:
            node.outputs[0].default_value = material['small'] if size <= rm.SMALL_SIZE else 1.


def bolt_material(kind, strength):
    g = Graph(f'rw-bolt-{kind}')
    if kind == 'core':
        return g.surface(g.emission(linear('f7f3ff'), 6.*strength))
    return g.surface(g.cover(g.emission(linear('9d8cff'), 1.6), .46*strength))


def curve(name, path, radius, material):
    data = bpy.data.curves.new(name, 'CURVE')
    data.dimensions = '3D'
    data.bevel_depth = radius
    data.bevel_resolution = 3
    spline = data.splines.new('POLY')
    spline.points.add(len(path)-1)
    for point, (x, y, z) in zip(spline.points, path):
        point.co = (x, y, z, 1)
    data.materials.append(material)
    return add(name, data)


def bolt_paths(spec, only=None):
    """The channels shown at this frame: the leader reaches part of the way, the flash shows them all."""
    main = spec['main']
    shown = max(2, round(len(main)*spec['reach']))
    paths = {'bolt-main': main[:shown]}
    for key, start in (('near', 4), ('twig', None), ('far', 3)):
        if start is None or start < shown:
            paths[f'bolt-{key}'] = spec[key]
    if only == 'bolt-near':
        return {k: v for k, v in paths.items() if k in ('bolt-near', 'bolt-twig')}
    if only == 'bolt-far':
        return {k: v for k, v in paths.items() if k == 'bolt-far'}
    return paths


def aurora_material(spec):
    g = Graph('rw-aurora')
    u, v, _ = g.xyz(g.coordinates('UV'))
    light = g.math('ADD', .5, g.math('MULTIPLY', .5, g.math('COSINE', g.math(
        'MULTIPLY', g.math('SUBTRACT', spec['phase']-spec['offset'], u), 2*math.pi))))
    rays = g.math('ADD', .62, g.math('MULTIPLY', .38, g.math('SINE', g.math(
        'MULTIPLY', g.math('ADD', g.math('MULTIPLY', u, 9.), 2*spec['phase']), 2*math.pi))))
    edge = g.smooth(v, 0., .06)
    fade = g.math('POWER', g.math('SUBTRACT', 1., v, clamp=True), 1.3)
    alpha = g.math('MULTIPLY', g.math('MULTIPLY', edge, fade),
                   g.math('MULTIPLY', g.math('ADD', .30, g.math('MULTIPLY', light, .70)), rays))
    colour = g.colour_mix(linear('63e59a'), linear('a98be6'), g.smooth(v, .35, .85))
    return g.surface(g.cover(g.emission(colour, 1.6), g.math('MULTIPLY', alpha, .92, clamp=True)))


def aurora_mesh(spec):
    co, faces, uv = [], [], []
    count = len(spec['base'])
    for i, (x, y) in enumerate(spec['base']):
        co += [(x, y, spec['depth']), (x, y+spec['height'], spec['depth'])]
        uv += [(i/(count-1), 0.), (i/(count-1), 1.)]
    faces = [(2*i, 2*i+2, 2*i+3, 2*i+1) for i in range(count-1)]
    mesh = bpy.data.meshes.new(spec['name'])
    mesh.from_pydata(co, [], faces)
    layer = mesh.uv_layers.new(name='UVMap')
    for poly in mesh.polygons:
        for loop in poly.loop_indices:
            layer.data[loop].uv = uv[mesh.loops[loop].vertex_index]
    return mesh


def lamp(spec):
    data = bpy.data.lights.new(spec['name'], 'SUN')
    data.energy = spec['strength']
    data.color = linear(spec['colour'])
    data.angle = math.radians(spec['angle'])
    obj = bpy.data.objects.new(spec['name'], data)
    collection().objects.link(obj)
    direction = WORLD[1] @ Vector(rm.normalized(spec['direction']))
    obj.rotation_euler = (-direction).to_track_quat('-Z', 'Y').to_euler()
    return obj


def link_lights(receivers, lamps):
    """The studio lights the kept solids as before; each lamp lights only the kinds it names."""
    studio_set = bpy.data.collections.get('rw-studio-excluded') or bpy.data.collections.new('rw-studio-excluded')
    for obj in list(studio_set.objects):
        studio_set.objects.unlink(obj)
    lit = [obj for objs in receivers.values() for obj in objs]
    for obj in lit:
        studio_set.objects.link(obj)
        # The link states follow the collection's object order; they take no name lookups.
        studio_set.collection_objects[list(studio_set.objects).index(obj)].light_linking.link_state = 'EXCLUDE'
    for name in STUDIO_LIGHTS:
        bpy.data.objects[name].light_linking.receiver_collection = studio_set if lit else None
    for spec in lamps:
        targets = [obj for kind in spec['receives'] for obj in receivers.get(kind, [])]
        if not targets:
            continue
        group = bpy.data.collections.new(f'rw-{spec["name"]}-lit')
        for obj in targets:
            group.objects.link(obj)
            group.collection_objects[list(group.objects).index(obj)].light_linking.link_state = 'INCLUDE'
        lamp(spec).light_linking.receiver_collection = group


def build(scene, record, only=None):
    """Make the scene's objects; only names one element (and its lamp) for an isolated feature render."""
    clear()
    shapes = {shape.name: shape for shape in WORLD[2]}
    receivers, lamps = {}, []
    for spec in scene:
        kind, name = spec['kind'], spec['name']
        if kind == 'lamp':
            lamps.append(spec)
            continue
        if only is not None and name != only and not (kind == 'bolt' and only in spec['features']):
            continue
        if kind == 'sun':
            obj = add(name, unit_sphere(), ellipsoid_matrix(spec))
            assign(obj, sun_material(spec, record))
        elif kind == 'corona':
            obj = add(name, unit_sphere(), ellipsoid_matrix(spec))
            assign(obj, corona_material(spec))
        elif kind == 'streamer':
            obj = add(name, tube_mesh(name, spec['start'], spec['end'], spec['radii']))
            assign(obj, streamer_material())
        elif kind == 'moon':
            turn = Matrix.Rotation(math.pi if spec['hemisphere'] == 'south' else 0, 4, 'Z')
            obj = add(name, moon_mesh(), ellipsoid_matrix(spec, turn))
            assign(obj, moon_material(spec))
            receivers.setdefault('moon', []).append(obj)
        elif kind in ('cloud', 'fog'):
            obj = add(name, unit_sphere(), ellipsoid_matrix(spec))
            assign(obj, volume_material(spec))
            receivers.setdefault(kind, []).append(obj)
        elif kind == 'bolt':
            core, sheath = bolt_material('core', spec['glow']), bolt_material('sheath', spec['glow'])
            if spec['glow'] > 0:
                for key, path in bolt_paths(spec, only if only in spec['features'] else None).items():
                    width = .011 if key == 'bolt-main' else .008
                    curve(key, path, width, core)
                    curve(key+'-glow', path, 4.2*width, sheath)
            if spec['cloud'] > 0 and only is None:
                data = bpy.data.lights.new('bolt-light', 'POINT')
                data.energy = 9.*spec['cloud']
                data.shadow_soft_size = .08
                data.color = linear('d9d0ff')
                add('bolt-light', data, Matrix.Translation(spec['light']))
        elif kind == 'aurora':
            obj = add(name, aurora_mesh(spec))
            assign(obj, aurora_material(spec))
        elif kind == 'solid':
            shape = shapes[name]
            mesh = bpy.data.meshes.new(name)
            mesh.from_pydata([tuple(p) for ring in shape.rings for p in ring], [], list(base.mesh_faces(shape)))
            for face in mesh.polygons:
                face.use_smooth = shape.smooth
            mesh.materials.append(base.coating(shape, SOLIDS))
            add(name, mesh)
    link_lights(receivers, lamps)


def solid_only(shape):
    """The modelled solid alone, as the hard witness of a volume's extent."""
    clear()
    link_lights({}, [])
    mesh = bpy.data.meshes.new(shape.name)
    mesh.from_pydata([tuple(p) for ring in shape.rings for p in ring], [], list(base.mesh_faces(shape)))
    mesh.materials.append(base.coating(shape, SOLIDS))
    add(shape.name, mesh)


def samples_for(size):
    """Volume noise shows most at the largest sizes: 96 samples at 256 px, 64 at 128 px, 32 below."""
    return 96 if size >= 256 else 64 if size >= 128 else 32


def timed_pair(size, camera, rig, exr, supersample, symbolic, costs, label):
    bpy.context.scene.cycles.samples = samples_for(size)
    size_materials(size)
    usage = resource.getrusage(resource.RUSAGE_SELF)
    start = time.monotonic()
    views = base.render_pair(size, camera, rig, exr, supersample, symbolic)
    after = resource.getrusage(resource.RUSAGE_SELF)
    costs.append(dict(label=label, size=size, samples=samples_for(size), wall_s=round(time.monotonic()-start, 3),
                      cpu_s=round(after.ru_utime+after.ru_stime-usage.ru_utime-usage.ru_stime, 3),
                      load=Path('/proc/loadavg').read_text().split()[0]))
    return views


def initialize(samples):
    # The studio starts from Blender's factory settings, which frees every cached mesh, image and material.
    CACHE.clear()
    SOLIDS.clear()
    cameras, right = base.initialize(samples)
    scene = bpy.context.scene
    scene.cycles.volume_bounces = 2
    # Ray marching: Blender 5.0's unbiased volumes spend about 10 s per view on fixed work at any size
    # (22 s against 0.8 s for a 64 px pair; the pictures differ by 0.006 on average).
    scene.cycles.volume_biased = True
    scene.cycles.transparent_max_bounces = 16
    return cameras, right


def features_for(params, poses, scene):
    visible = [shape for shape in poses[0] if shape.alpha >= .38]

    def depth(shape):
        return sum(point[2] for point in shape.outline)/len(shape.outline)
    chosen = {'near': max(visible, key=depth), 'far': min(visible, key=depth)}
    by = {spec['name']: spec for spec in scene}
    rows = {}
    for label, shape in chosen.items():
        real = rm.counterpart(shape.name, scene)
        if shape.name == 'bolt':
            real = 'bolt-near'
        spec = by.get(real)
        interval = spec['z'] if spec else next(s['features'][real] for s in scene if s['kind'] == 'bolt')
        rows[label] = dict(model=shape.name, name=real, extrema=list(interval),
                           witness=shape.name if spec and spec['kind'] in ('cloud', 'fog') else None)
    bolt = next((s for s in scene if s['kind'] == 'bolt'), None)
    if bolt:
        for key, interval in bolt['features'].items():
            rows[key] = dict(model='bolt', name=key, extrema=list(interval), witness=None)
    if any(s['kind'] == 'aurora' for s in scene):
        for key in ('aurora-0', 'aurora-2'):
            rows[key] = dict(model=key, name=key, extrema=list(by[key]['z']), witness=None)
    return rows


def render_name(name, out, scratch, sizes, loop_sizes, supersample, samples, static_only, variant):
    params = geo.parameters(name)
    params.update(variant)
    record = json.loads((SOURCES/'derivation.json').read_text())
    poses = [geo.model(params, i/base.FRAMES, base.DISC_BACK) for i in range(base.FRAMES+1)]
    scenes = [rm.specs(params, pose, i/base.FRAMES, base.DISC_BACK) for i, pose in enumerate(poses)]
    camera, bounds = base.cameras_for(params, poses, set(sizes+loop_sizes+(64, 256)))
    extents = {}
    for scene in scenes:
        for spec in scene:
            if spec['kind'] == 'lamp':
                continue
            low, high = extents.get(spec['name'], (9, -9))
            extents[spec['name']] = (min(low, spec['z'][0]), max(high, spec['z'][1]))
    outside = {k: v for k, v in extents.items() if v[0] < bounds[0]-1e-9 or v[1] > bounds[1]+1e-9}
    if outside:
        raise ValueError(f'{name}: real elements outside the modelled depth range {bounds}: {outside}')
    if rm.signature(scenes[-1]) != rm.signature(scenes[0]):
        raise ValueError(f'{name}: the real scene after the wrap differs from phase 0')
    out.mkdir(parents=True, exist_ok=True)
    scratch.mkdir(parents=True, exist_ok=True)
    cameras, right = initialize(samples)
    WORLD[:] = [Matrix.Translation(base.CENTRE) @ cameras['centre'].rotation_euler.to_matrix().to_4x4(),
                cameras['centre'].rotation_euler.to_matrix(), poses[0]]
    costs = []
    start = time.monotonic()
    for frame in range(base.FRAMES):
        selected = sizes if frame == 0 else loop_sizes
        if static_only and frame:
            break
        if params['family'] == 'status' and frame:
            for size in selected:
                shutil.copyfile(scratch/f'{size}-00.png', scratch/f'{size}-{frame:02}.png')
            continue
        WORLD[2] = poses[frame]
        build(scenes[frame], record)
        for size in selected:
            views = timed_pair(size, camera[size], (cameras, right), scratch/'eye.exr', supersample,
                               params.get('symbolic', False), costs, f'frame-{frame:02}')
            if frame == 0:
                write_png(out/f'{size}.pns', views, pair_mark=True)
            if not static_only and size in loop_sizes:
                write_png(scratch/f'{size}-{frame:02}.png', views)
        print('real-weather-frame', name, frame, f'{time.monotonic()-start:.1f}s', flush=True)
    features = {} if static_only else features_for(params, poses, scenes[0])
    WORLD[2] = poses[0]
    for label, row in features.items():
        build(scenes[0], record, only=row['name'])
        views = timed_pair(64, camera[64], (cameras, right), scratch/'edge.exr', supersample, False, costs, label)
        write_png(out/f'edge-{label}.pns', views, pair_mark=True)
        if row['witness']:
            solid_only(next(s for s in poses[0] if s.name == row['witness']))
            views = timed_pair(64, camera[64], (cameras, right), scratch/'edge.exr', supersample, False, costs,
                               f'witness-{label}')
            write_png(out/f'witness-{label}.pns', views, pair_mark=True)
    recipe = dict(look=rm.LOOK, name=name, parameters=params, bounds_z=bounds, real_extents=extents,
                  features=features, frames=base.FRAMES, delay_ms=100, frame_size=sizes, loop_sizes=loop_sizes,
                  camera=camera, distance=base.DISTANCE, hfov=studio.HFOV, supersample=supersample,
                  samples={size: samples_for(size) for size in sorted(set(sizes+loop_sizes+(64,)))},
                  scene=rm.signature(scenes[0]), costs=costs,
                  sources=record['files'], blender=bpy.app.version_string)
    (out/'geometry.json').write_text(json.dumps(recipe, indent=1)+'\n')


def rerender_edges(name, out, scratch, size):
    """Fit the features again at a larger size, as the thin flake branch of milestone 2 was: a feature only a few
    pixels across at 64 px gives too few samples for a stable horizontal fit. The 64 px renders are kept beside."""
    recipe_path = out/'geometry.json'
    recipe = json.loads(recipe_path.read_text())
    params = recipe['parameters']
    record = json.loads((SOURCES/'derivation.json').read_text())
    poses = [geo.model(params, i/base.FRAMES, base.DISC_BACK) for i in range(base.FRAMES+1)]
    scene = rm.specs(params, poses[0], 0, base.DISC_BACK)
    camera, _ = base.cameras_for(params, poses, {64, 256, size})
    scratch.mkdir(parents=True, exist_ok=True)
    cameras, right = initialize(recipe['samples'].get('64', 32) if isinstance(recipe['samples'], dict) else 32)
    WORLD[:] = [Matrix.Translation(base.CENTRE) @ cameras['centre'].rotation_euler.to_matrix().to_4x4(),
                cameras['centre'].rotation_euler.to_matrix(), poses[0]]
    costs = recipe.setdefault('costs', [])
    for label, row in recipe['features'].items():
        for prefix in ('edge', 'witness'):
            if (out/f'{prefix}-{label}.pns').exists() and not (out/f'{prefix}-{label}-64.pns').exists():
                (out/f'{prefix}-{label}.pns').rename(out/f'{prefix}-{label}-64.pns')
        build(scene, record, only=row['name'])
        views = timed_pair(size, camera[size], (cameras, right), scratch/'edge.exr', recipe['supersample'], False, costs,
                           f'{label}-{size}')
        write_png(out/f'edge-{label}.pns', views, pair_mark=True)
        if row.get('witness'):
            solid_only(next(s for s in poses[0] if s.name == row['witness']))
            views = timed_pair(size, camera[size], (cameras, right), scratch/'edge.exr', recipe['supersample'], False,
                               costs, f'witness-{label}-{size}')
            write_png(out/f'witness-{label}.pns', views, pair_mark=True)
        row['size'] = size
    recipe['camera'][str(size)] = camera[size]
    recipe_path.write_text(json.dumps(recipe, indent=1)+'\n')


WORLD = [Matrix(), Matrix(), []]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('scratch', type=Path)
    parser.add_argument('names', nargs='+')
    parser.add_argument('--sizes', type=int, nargs='+', default=base.SIZES)
    parser.add_argument('--loops', type=int, nargs='+', default=base.LOOP_SIZES)
    parser.add_argument('--supersample', type=int, default=2)
    parser.add_argument('--samples', type=int, default=32)
    parser.add_argument('--static-only', action='store_true')
    parser.add_argument('--no-streamers', action='store_true')
    parser.add_argument('--suffix', default='')
    parser.add_argument('--edges-only', type=int, choices=(256,))
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    variant = {'streamers': False} if args.no_streamers else {}
    for name in args.names:
        if args.edges_only:
            rerender_edges(name, args.output/name, args.scratch/name, args.edges_only)
            continue
        render_name(name, args.output/(name+args.suffix), args.scratch/(name+args.suffix), tuple(args.sizes),
                    tuple(args.loops), args.supersample, args.samples, args.static_only, variant)


if __name__ == '__main__':
    main()
