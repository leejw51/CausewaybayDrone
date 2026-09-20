"""Authored Olympic Park landmark likeness; dimensions in metres, details approximate."""

from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.context.scene.unit_settings.system = "METRIC"


def mat(name, color, roughness=0.65):
    material = bpy.data.materials.new(name)
    material.diffuse_color = (*color, 1)
    material.use_nodes = True
    material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (
        *color,
        1,
    )
    material.node_tree.nodes["Principled BSDF"].inputs[
        "Roughness"
    ].default_value = roughness
    return material


stone = mat("Warm limestone", (0.72, 0.68, 0.57))
roof = mat("Ivory wing roof", (0.87, 0.84, 0.72))
bronze = mat("Bronze reveals", (0.21, 0.14, 0.075), 0.4)
colors = [
    mat("Painted underside " + str(i), c)
    for i, c in enumerate(
        [
            (0.64, 0.12, 0.10),
            (0.055, 0.27, 0.37),
            (0.82, 0.53, 0.12),
            (0.12, 0.35, 0.23),
        ]
    )
]


def box(name, pos, size, material, bevel=0.08):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    o = bpy.context.object
    o.name = name
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(material)
    mod = o.modifiers.new("Soft stone edges", "BEVEL")
    mod.width = bevel
    mod.segments = 3
    o.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return o


# Broad rising wings with a low central saddle, 62 x 37 m, maximum height 24 m.
xs = [-31, -27, -22, -16, -9, 0, 9, 16, 22, 27, 31]
zs = [24, 23.05, 22.1, 21.25, 20.8, 20.5, 20.8, 21.25, 22.1, 23.05, 24]
verts = []
for x, z in zip(xs, zs):
    depth = 18.5 - 2.8 * (abs(x) / 31) ** 2
    verts.extend(
        [(x, -depth, z), (x, depth, z), (x, -depth, z - 1.35), (x, depth, z - 1.35)]
    )
faces = [(0, 2, 3, 1)]
for i in range(len(xs) - 1):
    a, b = i * 4, (i + 1) * 4
    faces.extend(
        [
            (a, b, b + 1, a + 1),
            (a + 2, a + 3, b + 3, b + 2),
            (a, a + 2, b + 2, b),
            (a + 1, b + 1, b + 3, a + 3),
        ]
    )
n = (len(xs) - 1) * 4
faces.append((n, n + 1, n + 3, n + 2))
mesh = bpy.data.meshes.new("Curved wing structure")
mesh.from_pydata(verts, [], faces)
mesh.update()
o = bpy.data.objects.new("Peace gate wing roof", mesh)
bpy.context.collection.objects.link(o)
o.data.materials.append(roof)
bev = o.modifiers.new("Roof edge softening", "BEVEL")
bev.width = 0.12
bev.segments = 3
o.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
for side in [-1, 1]:
    box("Foundation", (side * 18, 0, 0.35), (8, 11, 0.7), stone)
    box("Monument pier", (side * 18, 0, 10.1), (5.8, 8.5, 20.2), stone)
    for y in [-4.3, 4.3]:
        box("Recessed pier panel", (side * 18, y, 10), (4.5, 0.13, 16), bronze, 0.025)
        for j in range(7):
            box(
                "Pier relief",
                (side * 18, y * 1.02, 3.4 + j * 2.1),
                (3.9, 0.14, 0.055),
                stone,
                0.01,
            )
    # Original geometric colourwork suggests the decorated soffit without copying murals.
    for j in range(8):
        x = side * (3 + j * 3.4)
        z = 20.5 + 3.5 * (abs(x) / 31) ** 2 - 1.42
        ob = box(
            "Soffit colour inlay", (x, 0, z), (2.65, 26, 0.12), colors[j % 4], 0.025
        )
        ob.rotation_euler.y = -side * 0.09
box("Eternal flame plinth", (0, 0, 0.45), (3.4, 3.4, 0.9), stone)
box("Bronze flame bowl", (0, 0, 1.05), (1.8, 1.8, 0.3), bronze)
scene = bpy.context.scene
scene["provenance"] = (
    "Artist-authored likeness using existing mapped location; no NGII data. Ornament and pier geometry approximate."
)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "blender/world_peace_gate.blend"))
bpy.ops.export_scene.gltf(
    filepath=str(ROOT / "godot/assets/world-peace-gate.glb"),
    export_format="GLB",
    export_apply=True,
)
