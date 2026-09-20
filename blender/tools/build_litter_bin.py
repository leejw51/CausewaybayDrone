"""Blender-authored park bin and meal waste, with a Codex-generated enamel texture."""

import bpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, color):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (
        *color,
        1,
    )
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.52
    return m


teal = material("Codex hand-painted enamel", (0.03, 0.36, 0.32))
image = bpy.data.images.load(str(ROOT / "godot/assets/textures/bin-enamel-codex.png"))
image.pack()
tex = teal.node_tree.nodes.new("ShaderNodeTexImage")
tex.image = image
teal.node_tree.links.new(
    tex.outputs["Color"], teal.node_tree.nodes["Principled BSDF"].inputs["Base Color"]
)
cream = material("Warm cream rim", (0.93, 0.78, 0.45))
dark = material("Dark bin interior", (0.018, 0.035, 0.03))
paper = material("Used paper", (0.88, 0.8, 0.62))


def cube(name, location, scale, mat, bevel=0.035):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    o = bpy.context.object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    mod = o.modifiers.new("Soft toy edges", "BEVEL")
    mod.width = bevel
    mod.segments = 3
    o.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return o


parts = []
parts.append(cube("Base", (0, 0, 0.08), (0.62, 0.62, 0.16), dark))
for x in [-0.25, 0.25]:
    parts.append(cube("Side panel", (x, 0, 0.53), (0.10, 0.54, 0.90), teal))
for y in [-0.25, 0.25]:
    parts.append(cube("Front back panel", (0, y, 0.53), (0.44, 0.10, 0.90), teal))
for x in [-0.27, 0.27]:
    parts.append(cube("Opening rim", (x, 0, 1.0), (0.10, 0.64, 0.10), cream))
for y in [-0.27, 0.27]:
    parts.append(cube("Opening rim", (0, y, 1.0), (0.48, 0.10, 0.10), cream))
parts.append(cube("Interior bottom", (0, 0, 0.15), (0.44, 0.44, 0.04), dark))
bpy.ops.object.text_add(location=(-0.19, -0.308, 0.5), rotation=(1.5708, 0, 0))
o = bpy.context.object
o.name = "CB emblem"
o.data.body = "CB"
o.data.size = 0.21
o.data.extrude = 0.004
o.data.materials.append(cream)
bpy.ops.object.convert(target="MESH")
parts.append(bpy.context.object)


def export(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=str(ROOT / ("godot/assets/" + name + ".glb")),
        use_selection=True,
        export_format="GLB",
    )


export(parts, "park-litter-bin")
bpy.ops.mesh.primitive_ico_sphere_add(
    subdivisions=1, radius=0.12, location=(2, 0, 0.12)
)
wrapper = bpy.context.object
wrapper.name = "Crumpled sandwich wrapper"
wrapper.scale = (1.1, 0.8, 0.6)
wrapper.data.materials.append(paper)
wrapper.location = (0, 0, 0)
export([wrapper], "meal-wrapper")
wrapper.location = (2, 0, 0.12)
bpy.ops.mesh.primitive_cone_add(vertices=20, radius1=0.055, radius2=0.078, depth=0.18)
cup = bpy.context.object
cup.name = "Empty coffee cup"
cup.data.materials.append(paper)
export([cup], "empty-coffee-cup")
cup.location = (2.4, 0, 0.1)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "blender/park_litter_bin.blend"))
