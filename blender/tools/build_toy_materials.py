"""Codex-generated plastic material palette for the toy-brick art direction."""

from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
image = bpy.data.images.load(str(ROOT / "blender/textures/toy-plastic-codex.png"))
image.pack()
for i, (name, color) in enumerate(
    [
        ("Red", (0.75, 0.025, 0.015, 1)),
        ("Yellow", (1, 0.66, 0.015, 1)),
        ("Blue", (0.02, 0.18, 0.7, 1)),
        ("Green", (0.04, 0.42, 0.09, 1)),
        ("White", (0.9, 0.9, 0.86, 1)),
        ("Charcoal", (0.025, 0.03, 0.035, 1)),
    ]
):
    mat = bpy.data.materials.new("Codex ABS / " + name)
    mat.use_nodes = True
    n, links = mat.node_tree.nodes, mat.node_tree.links
    tex = n.new("ShaderNodeTexImage")
    tex.image = image
    tint = n.new("ShaderNodeMixRGB")
    tint.blend_type = "MULTIPLY"
    tint.inputs[0].default_value = 1
    tint.inputs[2].default_value = color
    links.new(tex.outputs["Color"], tint.inputs[1])
    bsdf = n.get("Principled BSDF")
    links.new(tint.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.28
    mat.diffuse_color = color
    x, y = (i % 3) * 3.0 - 3.0, (i // 3) * 2.6 - 1.3
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, 0.45))
    block = bpy.context.object
    block.name = name + " toy brick"
    block.dimensions = (2.4, 1.6, 0.9)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    block.data.materials.append(mat)
    bevel = block.modifiers.new("Soft molded edges", "BEVEL")
    bevel.width = 0.065
    bevel.segments = 3
    block.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    for dx in [-0.7, 0, 0.7]:
        for dy in [-0.4, 0.4]:
            bpy.ops.mesh.primitive_cylinder_add(
                vertices=32, radius=0.25, depth=0.18, location=(x + dx, y + dy, 0.99)
            )
            bpy.context.object.data.materials.append(mat)
bpy.ops.object.camera_add(location=(8, -11, 11))
cam = bpy.context.object
cam.rotation_euler = (
    (Vector((0, 0, 0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
)
cam.data.type = "ORTHO"
cam.data.ortho_scale = 12
scene = bpy.context.scene
scene.camera = cam
bpy.ops.object.light_add(type="AREA", location=(0, -3, 8))
bpy.context.object.data.energy = 1800
bpy.context.object.data.shape = "DISK"
bpy.context.object.data.size = 7
scene.world.color = (0.25, 0.25, 0.25)
scene.render.engine = "CYCLES"
scene.cycles.samples = 24
scene.render.resolution_x = 1000
scene.render.resolution_y = 800
scene.render.resolution_percentage = 100
scene.render.filepath = str(ROOT / "blender/toy-materials-preview.png")
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "blender/toy_materials.blend"))
bpy.ops.render.render(write_still=True)
