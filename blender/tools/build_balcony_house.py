"""Rounded park residence with an unobstructed balcony drone approach (+Z in Godot)."""

from pathlib import Path
import bpy

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
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.65
    return m


cream = material("Warm limestone", (0.77, 0.70, 0.55))
wood = material("Honey oak", (0.34, 0.18, 0.08))
teal = material("Patinated teal metal", (0.08, 0.28, 0.27))
glass = material("Blue window glazing", (0.13, 0.32, 0.4))
leaf = material("Planter greenery", (0.19, 0.40, 0.08))
white = material("Ivory trim", (0.93, 0.89, 0.76))


def box(name, p, size, mat, bevel=0.06):
    x, y, z = p
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, -z, y))
    ob = bpy.context.object
    ob.name = name
    ob.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.append(mat)
    mod = ob.modifiers.new("Soft architectural edges", "BEVEL")
    mod.width = bevel
    mod.segments = 3
    ob.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return ob


box("Residence", (0, 6, 0), (10, 12, 10), cream)
for y in [0.2, 4, 8, 12.15]:
    box("Floor cornice", (0, y, 0), (10.5, 0.25, 10.5), white)
box("Teal roof cap", (0, 12.4, 0), (10.8, 0.28, 10.8), teal)
for y in [2.2, 6.1, 10]:
    for x in [-3, 0, 3]:
        box("Window frame", (x, y, 5.12), (2.05, 2.45, 0.20), white)
        box("Window", (x, y, 5.25), (1.8, 2.2, 0.08), glass)
        box("Window mullion", (x, y, 5.32), (0.07, 2.2, 0.08), wood)
        box("Window sill", (x, y - 1.22, 5.32), (2.25, 0.12, 0.45), white)
    for x in [-5.12, 5.12]:
        for z in [-2.8, 1.3]:
            box("Side window frame", (x, y, z), (0.16, 2.45, 2), white)
            box(
                "Side glazing",
                (x + (0.09 if x > 0 else -0.09), y, z),
                (0.06, 2.2, 1.8),
                glass,
            )
box("Entry door", (0, 1.45, 5.38), (1.6, 2.8, 0.15), wood)
box("Entry canopy", (0, 3.15, 5.9), (3, 0.18, 2), teal)
box("Balcony slab", (0, 7.96, 7.7), (9, 0.3, 5.4), white)
for x in range(-4, 5):
    box("Balcony oak decking", (x, 8.14, 7.7), (0.96, 0.06, 5.2), wood, 0.015)
# Side rails leave the central aerial handoff corridor open.
for x in [-4.35, 4.35]:
    box("Balcony handrail", (x, 9.25, 7.7), (0.12, 0.12, 5.2), teal)
    for z in [5.4, 6.4, 7.4, 8.4, 9.4, 10.1]:
        box("Baluster", (x, 8.7, z), (0.08, 1.1, 0.08), teal)
for x in [-3.1, 3.1]:
    box("Front handrail", (x, 9.25, 10.25), (2.6, 0.12, 0.12), teal)
    for dx in [-1, 0, 1]:
        box("Front baluster", (x + dx, 8.7, 10.25), (0.08, 1.1, 0.08), teal)
    box("Planter", (x, 8.5, 5.8), (1.6, 0.7, 0.9), white)
    box("Shrub", (x, 9, 5.8), (1.4, 0.65, 0.7), leaf, 0.25)
box("Drone receiving pad", (0, 8.2, 9.4), (3.2, 0.08, 1.5), teal)
box("Pad marking", (0, 8.25, 9.4), (1.1, 0.015, 0.15), white, 0.01)
box("Balcony door", (0, 9.6, 5.39), (1.9, 2.8, 0.13), wood)
box("Balcony door glass", (0, 9.9, 5.48), (1.55, 1.8, 0.05), glass)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "blender/balcony_house.blend"))
bpy.ops.export_scene.gltf(
    filepath=str(ROOT / "godot/assets/balcony-house.glb"),
    export_format="GLB",
    export_apply=True,
)
