# SPDX-License-Identifier: GPL-3.0-only
"""Studio, contact shadow and the stereo camera pair. Run inside Blender (bpy)."""
import math

import bpy
from mathutils import Vector

AZIMUTH, ELEVATION, DISTANCE, HFOV = math.radians(34), math.radians(26), 4.2, math.radians(24)
# Total disparity from the farthest to the nearest point of the model, as a fraction of the picture width (one eye).
DEPTH_RANGE = 0.03


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def studio():
    """A gradient room with three soft boxes, so polished silver has something to reflect, plus a contact-shadow floor."""
    world = bpy.data.worlds.new("studio")
    world.use_nodes = True
    tree = world.node_tree
    for node in list(tree.nodes):
        tree.nodes.remove(node)
    out = tree.nodes.new("ShaderNodeOutputWorld")
    background = tree.nodes.new("ShaderNodeBackground")
    ramp = tree.nodes.new("ShaderNodeValToRGB")
    separate = tree.nodes.new("ShaderNodeSeparateXYZ")
    coord = tree.nodes.new("ShaderNodeTexCoord")
    tree.links.new(coord.outputs["Generated"], separate.inputs["Vector"])
    tree.links.new(separate.outputs["Z"], ramp.inputs["Fac"])
    ramp.color_ramp.elements[0].position = 0.25
    ramp.color_ramp.elements[0].color = (0.03, 0.035, 0.035, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (0.55, 0.58, 0.60, 1)
    background.inputs["Strength"].default_value = 0.8
    tree.links.new(ramp.outputs["Color"], background.inputs["Color"])
    tree.links.new(background.outputs["Background"], out.inputs["Surface"])
    bpy.context.scene.world = world

    def softbox(name, location, size, energy):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.active_object
        light.name = name
        light.data.shape = "RECTANGLE"
        light.data.size, light.data.size_y = size
        light.data.energy = energy
        direction = Vector((0, 0, 0.4)) - Vector(location)
        light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    softbox("key", (-2.6, -2.2, 3.4), (2.2, 2.2), 120)
    softbox("strip-right", (3.2, -0.6, 1.4), (0.5, 2.6), 90)
    softbox("rim", (0.8, 3.4, 1.8), (2.2, 0.6), 70)
    bpy.ops.mesh.primitive_plane_add(size=16, location=(0, 0, 0))
    floor = bpy.context.active_object
    floor.name = "floor"
    floor.is_shadow_catcher = True


def render_settings(samples):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 4
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "OPEN_EXR"
    scene.render.image_settings.color_depth = "32"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.filter_size = 1.0


def rig(target=Vector((0, 0, 0.5))):
    """Centre camera plus two eyes: parallel axes (the centre camera's), each eye offset along its right vector,
    with an off-axis (shifted) frustum so every point on the convergence plane has zero parallax. No toe-in."""
    scene = bpy.context.scene
    position = target + Vector((math.sin(AZIMUTH) * math.cos(ELEVATION), -math.cos(AZIMUTH) * math.cos(ELEVATION), math.sin(ELEVATION))) * DISTANCE
    forward = (target - position).normalized()
    rotation = forward.to_track_quat("-Z", "Y").to_euler()
    rotation_matrix = rotation.to_matrix()
    right = rotation_matrix @ Vector((1, 0, 0))
    width_at_plane = 2 * DISTANCE * math.tan(HFOV / 2)
    cameras = {}
    for eye, sign in (("centre", 0), ("left", -1), ("right", 1)):
        data = bpy.data.cameras.new(eye)
        data.sensor_fit = "HORIZONTAL"
        data.angle = HFOV
        obj = bpy.data.objects.new(eye, data)
        scene.collection.objects.link(obj)
        obj.rotation_euler = rotation
        cameras[eye] = obj
        obj.location = position
    return cameras, right, width_at_plane, position, forward


def evaluated_corners(objects):
    """World-space bounding-box corners of the objects as rendered, modifiers included."""
    graph = bpy.context.evaluated_depsgraph_get()
    for obj in objects:
        evaluated = obj.evaluated_get(graph)
        for corner in evaluated.bound_box:
            yield evaluated.matrix_world @ Vector(corner)


def depth_range(position, forward, objects):
    zs = [(corner - position).dot(forward) for corner in evaluated_corners(objects)]
    return min(zs), max(zs)


def separation(near, far):
    """The eye separation that spreads DEPTH_RANGE across the model: disparity(Z) = b * (D - Z) / Z, in units of the plane's width."""
    d = DISTANCE
    span = (d - near) / near - (d - far) / far
    return DEPTH_RANGE * (2 * d * math.tan(HFOV / 2)) / span


def place_eyes(cameras, right, width_at_plane, base):
    for eye, sign in (("left", -1), ("right", 1)):
        cameras[eye].location = cameras["centre"].location + right * (sign * base / 2)
        cameras[eye].data.shift_x = -sign * (base / 2) / width_at_plane
