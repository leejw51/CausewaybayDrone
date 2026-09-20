"""Real map terrain and a textured Lone Tree. Run inside Blender."""

import bpy
import json
import math
import random
from mathutils import Vector, Euler
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEXTURES = ROOT / "blender/textures"
data = json.loads((ROOT / "godot/data/real-map.json").read_text())
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, color, image=None, roughness=0.85):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Roughness"].default_value = roughness
    if image:
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(str(TEXTURES / image), check_existing=True)
        tex.image.pack()
        tex.extension = "REPEAT"
        links.new(tex.outputs["Color"], shader.inputs["Base Color"])
        # Procedural microrelief is intentionally separate from generated base color.
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 90
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.16
        bump.inputs["Distance"].default_value = 0.025
        links.new(noise.outputs["Fac"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], shader.inputs["Normal"])
    return mat


grass = material(
    "AI / Olympic Park lawn", (0.28, 0.4, 0.17), "adventure-grass-codex.png"
)
earth = material(
    "AI / Compacted park trail", (0.5, 0.4, 0.28), "adventure-path-codex.png"
)
bark = material("AI / Arborvitae bark", (0.3, 0.22, 0.15), "tree-bark.png")
city = material("Urban ground", (0.4, 0.41, 0.4))
concrete = material(
    "AI / Architectural concrete", (0.65, 0.63, 0.60), "architectural-concrete.png"
)
leaves = [
    material("Evergreen foliage " + str(i), color, "tree-foliage.png")
    for i, color in enumerate(
        [(0.16, 0.28, 0.09), (0.23, 0.36, 0.12), (0.28, 0.39, 0.15)]
    )
]


def mesh_object(name, vertices, faces, mat):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(mat)
    uv = mesh.uv_layers.new(name="Metre UV")
    for loop in mesh.loops:
        p = mesh.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = (p.x / 2, p.y / 2)
    return obj


t = data["terrain"]
nx, nz = t["nx"], t["nz"]
verts = [
    (t["x"] + i % nx * t["step"], -(t["z"] + i // nx * t["step"]), h)
    for i, h in enumerate(t["heights"])
]
faces = []
for z in range(nz - 1):
    for x in range(nx - 1):
        a = z * nx + x
        faces.extend([(a, a + nx, a + 1), (a + 1, a + nx, a + nx + 1)])
terrain = mesh_object("Olympic Park / map-derived terrain", verts, faces, grass)
terrain.data.materials.append(city)
for face in terrain.data.polygons:
    face.material_index = 0 if t["colors"][face.vertices[0]] else 1
    face.use_smooth = True
terrain["source"] = (
    "Preserved Mapzen Terrarium DEM / 15m resampling, not survey accuracy"
)
terrain["datum_m"] = data["origin"]["elevation_datum"]
for kind in ["grass", "pitch", "plaza"]:
    points = []
    for surface in data["surfaces"]:
        if surface["kind"] == kind:
            points.extend((p[0], -p[2], p[1]) for p in surface["triangles"])
    if points:
        mesh_object(
            "Mapped " + kind,
            points,
            [(i, i + 1, i + 2) for i in range(0, len(points), 3)],
            grass if kind != "plaza" else earth,
        )

# Reference: KSPO&CO's Lone Tree description (arborvitae, approx. 10 m).
# Irregular rounded crown and visible branching replace the tiered cone.
# Canopy widths and branching remain an artistic approximation, not a survey.
tree_parts = []
rng = random.Random(3739451104)


def branch(start, end, radius):
    start, end = Vector(start), Vector(end)
    direction = end - start
    bpy.ops.mesh.primitive_cone_add(
        vertices=10,
        radius1=radius,
        radius2=radius * 0.42,
        depth=direction.length,
        location=(start + end) / 2,
    )
    obj = bpy.context.object
    obj.name = "Tapered arborvitae branch"
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    obj.data.materials.append(bark)
    for face in obj.data.polygons:
        face.use_smooth = True
    tree_parts.append(obj)
    return obj


trunk = branch((0, 0, 0), (0.14, -0.08, 6.8), 0.36)
trunk.name = "Lone Tree trunk"
for i in range(24 if "--botanical" in __import__("sys").argv else 0):
    angle = i * 2.39996
    z = 2.1 + i * 0.23
    reach = 2.6 * math.sqrt(max(0.08, 1 - ((z - 5) / 4) ** 2))
    branch(
        (0.08, 0, z),
        (math.cos(angle) * reach, math.sin(angle) * reach, z + 0.9),
        0.13 * (1 - i / 35),
    )
# Keep the botanical variant available; toy adventure is the active art direction.
if "--botanical" in __import__("sys").argv:
    # Codex-generated transparent foliage cards retain fine botanical silhouettes.
    card = material(
        "Codex / Arborvitae spray", (0.3, 0.4, 0.2), "arborvitae-spray-codex.png"
    )
    card.surface_render_method = "DITHERED"
    card.use_backface_culling = False
    tex = next(n for n in card.node_tree.nodes if n.type == "TEX_IMAGE")
    card.node_tree.links.new(
        tex.outputs["Alpha"],
        card.node_tree.nodes.get("Principled BSDF").inputs["Alpha"],
    )
    vertices, faces = [], []
    for i in range(1250):
        z = rng.uniform(3.0, 9.3)
        section = math.sqrt(max(0.0, 1 - ((z - 5.85) / 3.8) ** 2))
        angle = i * 2.39996 + rng.uniform(-0.3, 0.3)
        radial = section * rng.uniform(0.20, 1.0)
        center = Vector(
            (
                math.cos(angle) * 2.65 * radial + 0.17 * (z - 5),
                math.sin(angle) * 2.5 * radial,
                z,
            )
        )
        size = rng.uniform(0.65, 1.10)
        rotation = Euler(
            (rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), angle)
        ).to_matrix()
        for cross in [0, math.pi / 2]:
            turn = Euler((0, 0, cross)).to_matrix()
            start = len(vertices)
            for v in [(-0.5, 0, -0.5), (0.5, 0, -0.5), (0.5, 0, 0.5), (-0.5, 0, 0.5)]:
                vertices.append(center + rotation @ turn @ (Vector(v) * size))
            faces.append((start, start + 1, start + 2, start + 3))
    mesh = bpy.data.meshes.new("Crossed botanical foliage cards")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(card)
    uv = mesh.uv_layers.new(name="UVMap")
    for face in mesh.polygons:
        for loop, coord in zip(face.loop_indices, [(0, 0), (1, 0), (1, 1), (0, 1)]):
            uv.data[loop].uv = coord
    obj = bpy.data.objects.new("Codex transparent foliage canopy", mesh)
    bpy.context.collection.objects.link(obj)
    tree_parts.append(obj)
else:
    toy_colors = [(0.10, 0.36, 0.055), (0.20, 0.49, 0.065), (0.30, 0.57, 0.09)]
    toy_leaves = [
        material("Toy canopy " + str(i), color, roughness=0.3)
        for i, color in enumerate(toy_colors)
    ]
    for i, (x, y, z, width) in enumerate(
        [
            (-1.1, 0, 4.8, 3.8),
            (1.1, 0.15, 5.3, 3.6),
            (0, -1.0, 6.3, 3.8),
            (-0.8, 0.7, 7.1, 3.4),
            (0.9, 0.6, 7.6, 3.1),
            (0, -0.2, 8.7, 2.7),
        ]
    ):
        bpy.ops.mesh.primitive_uv_sphere_add(
            segments=24, ring_count=16, radius=1, location=(x, y, z)
        )
        obj = bpy.context.object
        obj.name = "Soft storybook canopy"
        obj.scale = (width * 0.5, width * 0.44, width * 0.46)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        obj.data.materials.append(toy_leaves[i % 3])
        for face in obj.data.polygons:
            face.use_smooth = True
        tree_parts.append(obj)
    bark.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value = 0.36
    for link in list(bark.node_tree.links):
        if link.to_socket.name in ["Base Color", "Normal"]:
            bark.node_tree.links.remove(link)
    bark.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (
        0.24,
        0.105,
        0.035,
        1,
    )
# One mesh with shared material slots keeps the simulator's draw cost bounded.
bpy.ops.object.select_all(action="DESELECT")
for obj in tree_parts:
    obj.select_set(True)
bpy.context.view_layer.objects.active = trunk
bpy.ops.object.join()
# Pin the ground origin and normalize overall height to the published ~10 m.
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
height = max(v.co.z for v in trunk.data.vertices)
for vertex in trunk.data.vertices:
    vertex.co *= 10.0 / height
trunk["reference"] = "https://www.ksponco.or.kr/menu.es?mid=a20107010000"
trunk["height_m"] = 10.0
trunk["geometry_accuracy"] = "Photo-informed approximation; not measured branching"
tree_parts = [trunk]
bpy.ops.object.select_all(action="DESELECT")
for obj in tree_parts:
    obj.select_set(True)
bpy.context.view_layer.objects.active = trunk
(ROOT / "godot/assets").mkdir(exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=str(ROOT / "godot/assets/lone-tree.glb"),
    export_format="GLB",
    use_selection=True,
)
landmark = next(x for x in data["landmarks"] if x["name"] == "LONE TREE")
p = landmark["position"]
for obj in tree_parts:
    obj.location += __import__("mathutils").Vector((p[0], -p[2], p[1]))
# Material samples are retained in the Blender project for direct authoring.
for i, mat in enumerate([grass, earth, bark, concrete]):
    obj = mesh_object(
        "Material preview / " + mat.name,
        [(i * 3, 4, 0), (i * 3 + 2, 4, 0), (i * 3 + 2, 6, 0), (i * 3, 6, 0)],
        [(0, 1, 2, 3)],
        mat,
    )
    obj.hide_render = True
bpy.ops.object.camera_add(location=(p[0] + 23, -p[2] + 24, p[1] + 12))
cam = bpy.context.object
from mathutils import Vector

cam.rotation_euler = (
    (Vector((p[0], -p[2], p[1] + 4)) - cam.location).to_track_quat("-Z", "Y").to_euler()
)
bpy.context.scene.camera = cam
bpy.ops.object.light_add(type="SUN", location=(0, 0, 100))
bpy.context.object.rotation_euler = (0.5, -0.4, -0.5)
bpy.context.object.data.energy = 2
bpy.context.scene.world.color = (0.22, 0.28, 0.35)
bpy.context.scene.render.engine = "CYCLES"
bpy.context.scene.cycles.samples = 32
if (
    ROOT / "godot/assets/park-dressing.glb"
).exists() and "--rebuild-dressing" not in __import__("sys").argv:
    bpy.ops.import_scene.gltf(filepath=str(ROOT / "godot/assets/park-dressing.glb"))
else:
    exec(
        compile(
            (ROOT / "blender/tools/park_dressing.py").read_text(),
            "park_dressing.py",
            "exec",
        )
    )
bpy.ops.wm.save_as_mainfile(
    filepath=str(ROOT / "blender/olympic_park_environment.blend")
)
print(
    "BLENDER_PARK_TEXTURES_OK: packed grass, earth, bark; real terrain; exported tree"
)
