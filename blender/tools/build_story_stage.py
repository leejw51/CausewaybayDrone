"""Original miniature Rust Con park stage for story cinematics."""

import bpy, math, random
from pathlib import Path

R = Path(__file__).resolve().parents[2]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
random.seed(17)


def mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Roughness"].default_value = 0.65
    return m


jade = mat("Jade enamel", (0.025, 0.35, 0.31))
cream = mat("Vanilla", (0.94, 0.8, 0.5))
wood = mat("Warm cedar", (0.43, 0.20, 0.07))
grass = mat("Velvet lawn", (0.29, 0.52, 0.12))
navy = mat("Midnight blue", (0.04, 0.08, 0.2))
gold = mat("Golden stars", (0.98, 0.57, 0.07))
coral = mat("Coral", (0.9, 0.2, 0.13))
pink = mat("Petals", (0.96, 0.45, 0.65))


def finish(o, n, m, b=0.04):
    o.name = n
    o.data.materials.append(m)
    if b:
        mod = o.modifiers.new("Rounded game silhouette", "BEVEL")
        mod.width = b
        mod.segments = 3
        o.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return o


def box(n, p, d, m, b=0.04):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(p[0], -p[2], p[1]))
    o = bpy.context.object
    o.scale = (d[0], d[2], d[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, n, m, b)


def cylinder(n, p, r, h, m):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=96, radius=r, depth=h, location=(p[0], -p[2], p[1])
    )
    return finish(bpy.context.object, n, m)


cylinder("Floating park plinth", (0, -0.38, 0), 8.5, 0.7, wood)
cylinder("Gold edge band", (0, -0.08, 0), 8.55, 0.12, cream)
cylinder("Soft lawn", (0, 0, 0), 8.48, 0.12, grass)
for x in range(-7, 8):
    box("Path paving", (x * 0.85, 0.085, 2.1), (0.81, 0.055, 1.1), cream, 0.07)
# Friendly cafe booth behind the protagonists.
box("Cafe body", (-4, 0.75, -3), (2.8, 1.4, 1.5), jade, 0.12)
box("Cafe counter", (-4, 1.52, -2.75), (3.1, 0.16, 1.7), wood, 0.08)
for x in [-5.3, -2.7]:
    box("Canopy post", (x, 2.0, -3), (0.11, 1.8, 0.11), cream)
for i in range(7):
    box(
        "Candy striped canopy",
        (-5.4 + i * 0.46, 2.87, -3),
        (0.47, 0.18, 2.0),
        cream if i % 2 == 0 else coral,
        0.06,
    )
box("Cafe sign", (-4, 2.35, -2.9), (1.95, 0.52, 0.10), navy)
bpy.ops.object.text_add(location=(-4.78, 2.82, 2.22), rotation=(math.pi / 2, 0, 0))
o = bpy.context.object
o.data.body = "CB CAFE"
o.data.size = 0.30
o.data.extrude = 0.009
o.data.materials.append(cream)
bpy.ops.object.convert(target="MESH")
for x in [-5.8, 5.5]:
    for z in [-0.5, -0.22, 0.06]:
        box("Bench slat", (x, 0.5, z), (1.8, 0.08, 0.22), wood)
    for dx in [-0.65, 0.65]:
        box("Bench foot", (x + dx, 0.25, -0.22), (0.12, 0.5, 0.55), navy)
    box("Bench back", (x, 0.95, -0.5), (1.8, 0.32, 0.08), wood)
for x in [-6, 6]:
    box("Festival post", (x, 1.6, -3.8), (0.09, 3.2, 0.09), wood)
for i in range(17):
    x = -6 + i * 0.75
    y = 2.85 + 0.25 * (abs(x) / 6) ** 2
    box("Bunting string", (x, y, -3.8), (0.78, 0.025, 0.025), cream, 0.005)
    mesh = bpy.data.meshes.new("Pennant")
    mesh.from_pydata(
        [(x - 0.27, 3.8, y - 0.04), (x + 0.27, 3.8, y - 0.04), (x, 3.8, y - 0.5)],
        [],
        [(0, 1, 2)],
    )
    mesh.update()
    o = bpy.data.objects.new("Festival pennant", mesh)
    bpy.context.collection.objects.link(o)
    o.data.materials.append([gold, coral, jade][i % 3])
for i in range(45):
    a = random.uniform(0, math.tau)
    r = random.uniform(6.5, 8)
    x, z = math.cos(a) * r, math.sin(a) * r
    cylinder("Flower stem", (x, 0.18, z), 0.018, 0.25, jade)
    for j in range(5):
        q = j * math.tau / 5
        bpy.ops.mesh.primitive_uv_sphere_add(
            segments=8,
            ring_count=4,
            radius=0.085,
            location=(x + math.cos(q) * 0.075, -z + math.sin(q) * 0.075, 0.32),
        )
        finish(bpy.context.object, "Flower petal", pink if i % 2 else cream, 0)
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=8, ring_count=4, radius=0.05, location=(x, -z, 0.35)
    )
    finish(bpy.context.object, "Flower center", gold, 0)
bpy.ops.wm.save_as_mainfile(filepath=str(R / "blender/story_stage.blend"))
bpy.ops.export_scene.gltf(
    filepath=str(R / "godot/assets/story-stage.glb"), export_format="GLB"
)
print("STORY_STAGE_EXPORTED")
