# SPDX-License-Identifier: GPL-3.0-only
"""Original 3D models for the Kubabbar Glass icon set. Run inside Blender (bpy).

Every model is built from primitives with fixed seeds, in metres-free "icon units": the object fits a unit box around the origin,
standing on z = 0, so the camera rig and the contact shadow do not depend on the model.
"""
import math
import random

import bpy
import bmesh
from mathutils import Vector


def metal(name, rough=0.28, aniso=0.55, tint=(0.80, 0.82, 0.80)):
    """Brushed silver: the brush runs round the object's Z axis (a radial tangent), so highlights stretch across the ribs."""
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    tree = material.node_tree
    for node in list(tree.nodes):
        tree.nodes.remove(node)
    out = tree.nodes.new("ShaderNodeOutputMaterial")
    bsdf = tree.nodes.new("ShaderNodeBsdfPrincipled")
    tangent = tree.nodes.new("ShaderNodeTangent")
    tangent.direction_type = "RADIAL"
    tangent.axis = "Z"
    bsdf.inputs["Base Color"].default_value = (*tint, 1)
    bsdf.inputs["Metallic"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Anisotropic"].default_value = aniso
    tree.links.new(tangent.outputs["Tangent"], bsdf.inputs["Tangent"])
    tree.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return material


def paper(name, warm=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.93 + warm, 0.93, 0.90 - warm, 1)
    bsdf.inputs["Roughness"].default_value = 0.85
    return material


def smooth(obj, levels=1):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth()
    if levels:
        modifier = obj.modifiers.new("subsurf", "SUBSURF")
        modifier.levels = levels
        modifier.render_levels = levels
    obj.select_set(False)


def torus(name, major, minor, z, material, segments=96):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=segments, minor_segments=24, location=(0, 0, z))
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(material)
    bpy.ops.object.shade_smooth()
    return obj


def bin_body(steel, inside):
    """A tapered silver bin, open at the top: a shell with a rolled rim, three stamped ribs and a base ring."""
    height, r_bottom, r_top = 1.1, 0.40, 0.50
    bpy.ops.mesh.primitive_cone_add(vertices=128, radius1=r_bottom, radius2=r_top, depth=height, end_fill_type="NOTHING", location=(0, 0, height / 2))
    shell = bpy.context.active_object
    shell.name = "bin-shell"
    shell.data.materials.append(steel)
    solid = shell.modifiers.new("solidify", "SOLIDIFY")
    solid.thickness = 0.022
    solid.offset = -1
    bpy.ops.object.shade_smooth()
    # the inside is the other side of the shell: give it its own, darker, metal
    shell.data.materials.append(inside)
    for polygon in shell.data.polygons:
        polygon.material_index = 0
    torus("bin-rim", r_top, 0.034, height, steel)
    torus("bin-foot", r_bottom + 0.012, 0.03, 0.03, steel)
    for index, t in enumerate((0.28, 0.5, 0.72)):
        radius = r_bottom + (r_top - r_bottom) * t
        torus("bin-rib-%d" % index, radius + 0.004, 0.017, height * t, steel)
    return height, r_top


def crumpled(name, location, radius, seed, material):
    rng = random.Random(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4, radius=radius, location=location)
    obj = bpy.context.active_object
    obj.name = name
    bpy.ops.object.shade_smooth()
    texture = bpy.data.textures.new(name + "-tex", "CLOUDS")
    texture.noise_scale = 0.34 * radius / 0.2
    texture.noise_depth = 3
    displace = obj.modifiers.new("crumple", "DISPLACE")
    displace.texture = texture
    displace.strength = radius * 0.9
    displace.mid_level = 0.45
    obj.rotation_euler = (rng.uniform(0, 3), rng.uniform(0, 3), rng.uniform(0, 3))
    obj.data.materials.append(material)
    return obj


def sheet(name, location, rotation, width, height, bend, seed, material):
    """A bent, softly crumpled sheet of paper, built vertex by vertex so its shape does not depend on modifier origins."""
    rng = random.Random(seed)
    phases = [(rng.uniform(0, 6.28), rng.uniform(0, 6.28), rng.uniform(1.2, 2.6)) for _ in range(3)]
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    builder = bmesh.new()
    nx, ny = 14, 18
    rows = []
    for j in range(ny + 1):
        row = []
        for i in range(nx + 1):
            u, v = 2 * i / nx - 1, 2 * j / ny - 1
            z = bend * width * 0.5 * u * u
            z += sum(0.018 * math.sin(f * u * 3.1 + a) * math.cos(f * v * 3.1 + b) for a, b, f in phases)
            row.append(builder.verts.new((u * width / 2, v * height / 2, z)))
        rows.append(row)
    for j in range(ny):
        for i in range(nx):
            builder.faces.new((rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i]))
    builder.to_mesh(mesh)
    builder.free()
    obj.location = location
    obj.rotation_euler = rotation
    solid = obj.modifiers.new("solid", "SOLIDIFY")
    solid.thickness = 0.006
    obj.data.materials.append(material)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth()
    obj.select_set(False)
    return obj


def trash_empty():
    steel, inside = metal("silver"), metal("silver-inside", rough=0.5, aniso=0.2, tint=(0.34, 0.35, 0.34))
    bin_body(steel, inside)


def trash_full():
    steel, inside = metal("silver"), metal("silver-inside", rough=0.5, aniso=0.2, tint=(0.34, 0.35, 0.34))
    height, r_top = bin_body(steel, inside)
    white, warm = paper("paper"), paper("paper-warm", 0.03)
    crumpled("ball-top", (0.0, 0.0, height + 0.1), 0.25, 21, warm)
    for index in range(5):
        angle = 2 * math.pi * index / 5 + 0.4
        crumpled("ball-%d" % index, (0.27 * math.cos(angle), 0.27 * math.sin(angle), height - 0.02), 0.2, 11 + index, white if index % 2 else warm)
    sheet("sheet-0", (0.12, -0.05, height + 0.2), (math.radians(80), math.radians(4), math.radians(-24)), 0.34, 0.5, 0.5, 5, white)
    sheet("sheet-1", (-0.16, 0.04, height + 0.15), (math.radians(74), math.radians(-6), math.radians(32)), 0.3, 0.44, -0.45, 9, warm)


def calibration(target, right, forward, rotation):
    """Two emissive crosses facing the camera for the stereo rig check: one on the convergence plane (zero parallax expected),
    one 0.4 units nearer (crossed parallax expected). Each sits on a dark square so a block match has contrast."""
    emitter = bpy.data.materials.new("cross")
    emitter.use_nodes = True
    nodes = emitter.node_tree.nodes
    for node in list(nodes):
        nodes.remove(node)
    out = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Strength"].default_value = 6.0
    emitter.node_tree.links.new(emission.outputs["Emission"], out.inputs["Surface"])
    dark = bpy.data.materials.new("backing")
    dark.use_nodes = True
    dark.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.01, 0.01, 0.01, 1)
    places = {"plane": target + right * 0.35, "near": target - right * 0.35 - forward * 0.4}
    for name, at in places.items():
        for part, scale, material, offset in (("backing", (0.24, 0.24, 0.004), dark, 0.0), ("bar-h", (0.18, 0.03, 0.004), emitter, 0.01), ("bar-v", (0.03, 0.18, 0.004), emitter, 0.01)):
            bpy.ops.mesh.primitive_cube_add(size=1, location=at - forward * offset, rotation=rotation)
            obj = bpy.context.active_object
            obj.name = "%s-%s" % (name, part)
            obj.scale = scale
            obj.data.materials.append(material)


MODELS = {"user-trash": trash_empty, "user-trash-full": trash_full}
