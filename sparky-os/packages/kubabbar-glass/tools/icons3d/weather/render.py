# SPDX-License-Identifier: GPL-3.0-only
"""Render authored weather geometry through the Kubabbar Glass camera and studio."""
import argparse
import json
import math
import os
from pathlib import Path
import sys
import time

import bpy
from mathutils import Vector
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import scene as studio
sys.path.insert(0, str(Path(__file__).resolve().parent))
from geometry import model, parameters
from picture import draw_svg, join_report, write_png

CENTRE = Vector((0, 0, .62))
DISTANCE = 1.12 / math.tan(studio.HFOV/2) * .98
DISC_BACK = 1/(2/DISTANCE-1/(DISTANCE-.36))-DISTANCE
FRAMES = 12
SIZES = (16, 22, 24, 32, 48, 64, 128, 256)
LOOP_SIZES = (64, 256)


def linear(srgb):
    return srgb / 12.92 if srgb <= 0.04045 else ((srgb + 0.055)/1.055)**2.4


def coating(shape, materials):
    key = shape.colour, shape.alpha, shape.name.startswith(('solar','ray','star','crescent','bolt'))
    if key in materials:
        return materials[key]
    colour, alpha, luminous = key
    rgb = tuple(linear(int(colour[i:i+2],16)/255) for i in (0,2,4))
    material = bpy.data.materials.new(shape.name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*rgb,1)
    bsdf.inputs['Roughness'].default_value = .34 if luminous else .51
    bsdf.inputs['Metallic'].default_value = .14 if luminous else .02
    bsdf.inputs['Emission Color'].default_value = (*rgb,1)
    bsdf.inputs['Emission Strength'].default_value = .58 if luminous else .14
    bsdf.inputs['Alpha'].default_value = alpha
    materials[key] = material
    return material


def mesh_faces(shape):
    n, count = len(shape.rings[0]), len(shape.rings)
    yield tuple(range(n))
    for ring in range(count-1):
        i = ring*n
        for j in range(n):
            k = (j+1)%n
            yield i+j, i+j+n, i+k+n, i+k
    yield tuple(reversed(range((count-1)*n,count*n)))


def set_geometry(shapes, basis, previous, materials):
    for obj in previous:
        mesh = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.meshes.remove(mesh)
    objects = []
    for shape in shapes:
        if shape.alpha == 0:
            continue
        mesh = bpy.data.meshes.new(shape.name)
        points = [CENTRE+basis@Vector(point) for ring in shape.rings for point in ring]
        mesh.from_pydata(points, [], list(mesh_faces(shape)))
        mesh.update()
        for face in mesh.polygons:
            face.use_smooth = shape.smooth
        obj = bpy.data.objects.new(shape.name,mesh)
        bpy.context.scene.collection.objects.link(obj)
        mesh.materials.append(coating(shape, materials))
        objects.append(obj)
    return objects


def cameras_for(parameters, phases, sizes):
    bounds = [point[2] for pose in phases for shape in pose for ring in shape.rings for point in ring]
    zmin, zmax = min(bounds), max(bounds)
    popped, sunk = studio.CANDIDATES[os.environ.get('ICON_RANGE', 'a')]
    camera = {size: studio.separation(DISTANCE-zmax, DISTANCE-zmin, size, popped, sunk)
              for size in sizes}
    if parameters['family'] == 'status':
        camera = {size: (0,DISTANCE) for size in sizes}
    return camera,(zmin,zmax)


def image_data(exr, size, sample_scale):
    image = bpy.data.images.load(str(exr))
    image.colorspace_settings.name = 'Non-Color'
    side = size*sample_scale
    values = np.empty(side*side*4, dtype=np.float32)
    image.pixels.foreach_get(values)
    bpy.data.images.remove(image)
    rgba = values.reshape(side,side,4)[::-1].reshape(size,sample_scale,size,sample_scale,4).mean(axis=(1,3))
    alpha = np.clip(rgba[...,3:4],0,1)
    colour = np.clip(rgba[...,:3]/np.maximum(alpha,1e-6),0,1)
    srgb = np.where(colour<=.0031308,colour*12.92,1.055*colour**(1/2.4)-.055)
    return np.rint(np.concatenate((srgb,alpha),axis=2)*65535).astype(np.uint16)


def render_pair(size, camera, rig, exr, supersample):
    base, convergence = camera
    cameras, right = rig
    studio.place_eyes(cameras,right,2*convergence*math.tan(studio.HFOV/2),base)
    scene = bpy.context.scene
    scene.render.resolution_x = scene.render.resolution_y = size*supersample
    scene.render.filepath = str(exr)
    views = []
    for eye in ('left','right'):
        scene.camera = cameras[eye]
        bpy.ops.render.render(write_still=True)
        views.append(image_data(exr,size,supersample))
    exr.unlink()
    return views


def render_name(name, out, scratch, sizes, loop_sizes, supersample, samples, static_only):
    start = time.monotonic()
    params = parameters(name)
    phases = [model(params,i/FRAMES,DISC_BACK) for i in range(FRAMES+1)]
    out.mkdir(parents=True, exist_ok=True)
    scratch.mkdir(parents=True, exist_ok=True)
    camera,bounds = cameras_for(params,phases,set(sizes+loop_sizes+(64,256)))
    join = join_report(params,phases,DISC_BACK)
    draw_svg(out/'static.svg',phases[:1],camera[64],DISTANCE,studio.HFOV)
    draw_svg(out/'loop.svg',phases[:-1],camera[64],DISTANCE,studio.HFOV)
    studio.reset()
    studio.DISTANCE = DISTANCE
    studio.studio()
    bpy.data.objects.remove(bpy.data.objects['floor'],do_unlink=True)
    cameras,right,*_ = studio.rig(CENTRE)
    studio.render_settings(samples)
    scene = bpy.context.scene
    scene.cycles.seed = 19
    scene.cycles.use_animated_seed = False
    scene.cycles.max_bounces = 4
    scene.render.use_persistent_data = True
    objects, materials = [], {}
    for frame, shapes in enumerate(phases[:-1]):
        selected = sizes if frame==0 else loop_sizes
        if static_only and frame !=0:
            break
        if not selected:
            continue
        objects = set_geometry(shapes,cameras['centre'].rotation_euler.to_matrix(),objects,materials)
        for size in selected:
            dest = scratch/f'{size}-{frame:02}.png'
            views = render_pair(size,camera[size],(cameras,right),scratch/'eye.exr',supersample)
            if frame==0:
                write_png(out/f'{size}.pns',views,pair_mark=True)
            if not static_only and size in loop_sizes:
                write_png(dest,views)
        print('weather-frame', name, frame, f'{time.monotonic()-start:.2f}s', flush=True)
    features = {}
    if not static_only:
        visible = [shape for shape in phases[0] if shape.alpha >= .38]
        def depth(shape):
            return sum(point[2] for point in shape.outline)/len(shape.outline)
        for label, feature in (('near',max(visible,key=depth)),('far',min(visible,key=depth))):
            objects = set_geometry([feature],cameras['centre'].rotation_euler.to_matrix(),objects,materials)
            views = render_pair(64,camera[64],(cameras,right),scratch/'edge.exr',supersample)
            write_png(out/f'edge-{label}.pns',views,pair_mark=True)
            zs = [point[2] for ring in feature.rings for point in ring]
            features[label] = dict(name=feature.name,z=depth(feature),extrema=[min(zs),max(zs)])
    recipe = dict(name=name,parameters=params,bounds_z=bounds,join=join,features=features,frames=FRAMES,delay_ms=100,
                  frame_size=sizes,loop_sizes=loop_sizes,camera=camera,distance=DISTANCE,hfov=studio.HFOV,
                  supersample=supersample,samples=samples,load=Path('/proc/loadavg').read_text().strip())
    (out/'geometry.json').write_text(json.dumps(recipe,indent=2)+'\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path)
    parser.add_argument('scratch',type=Path)
    parser.add_argument('names',nargs='+')
    parser.add_argument('--sizes',type=int,nargs='+',default=SIZES)
    parser.add_argument('--loops',type=int,nargs='+',default=LOOP_SIZES)
    parser.add_argument('--supersample',type=int,default=2)
    parser.add_argument('--samples',type=int,default=12)
    parser.add_argument('--static-only',action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    for name in args.names:
        render_name(name,args.output/name,args.scratch/name,tuple(args.sizes),tuple(args.loops),
                    args.supersample,args.samples,args.static_only)


if __name__=='__main__':
    main()
