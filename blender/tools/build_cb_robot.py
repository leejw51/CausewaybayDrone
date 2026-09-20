"""1.80 m CB service humanoid, separate shoulder pivots for Godot work animation."""

from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0


def material(name, color, rough=0.3, metal=0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.diffuse_color = (*color, 1)
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    return m


white = material("CB pearl ceramic polymer", (0.83, 0.86, 0.84))
black = material("CB graphite joint elastomer", (0.022, 0.028, 0.034), 0.42)
visor = material("CB smoked sensor visor", (0.009, 0.018, 0.024), 0.16, 0.22)
metal = material("CB satin joint alloy", (0.26, 0.32, 0.34), 0.28, 0.65)
teal = material("CB teal service lights", (0.01, 0.64, 0.56), 0.25)
p = teal.node_tree.nodes.get("Principled BSDF")
p.inputs["Emission Color"].default_value = (0.01, 0.5, 0.4, 1)
p.inputs["Emission Strength"].default_value = 0.5
badge = material("CB generated chest badge", (0.9, 0.9, 0.88))
tex = badge.node_tree.nodes.new("ShaderNodeTexImage")
tex.image = bpy.data.images.load(
    str(ROOT / "blender/textures/cb-robot-badge-codex.png")
)
tex.image.pack()
badge.node_tree.links.new(
    tex.outputs["Color"],
    badge.node_tree.nodes.get("Principled BSDF").inputs["Base Color"],
)
root = bpy.data.objects.new("CB_Robot", None)
bpy.context.collection.objects.link(root)
root["height_m"] = 1.8
root["design"] = (
    "Original CB humanoid, Optimus-inspired proportions, not Tesla hardware"
)


def parent(obj, par):
    # Evaluate freshly positioned empty pivots before preserving world space.
    bpy.context.view_layer.update()
    matrix = obj.matrix_world.copy()
    obj.parent = par
    obj.matrix_world = matrix


def box(name, at, size, mat, par=root, bevel=0.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    o = bpy.context.object
    o.name = name
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    b = o.modifiers.new("Soft manufactured edge", "BEVEL")
    b.width = bevel
    b.segments = 3
    o.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    parent(o, par)
    return o


def joint(name, at, r, par=root):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=20, ring_count=12, radius=r, location=at
    )
    o = bpy.context.object
    o.name = name
    o.data.materials.append(black)
    for f in o.data.polygons:
        f.use_smooth = True
    parent(o, par)
    return o


# Front is Blender -Y, exported as Godot +Z. Soles at z=0, crown at z=1.80.
for side in [-1, 1]:
    x = side * 0.115
    box("Sole", (x, -0.04, 0.025), (0.17, 0.30, 0.05), black, bevel=0.018)
    box("Foot shell", (x, -0.065, 0.075), (0.16, 0.28, 0.10), white, bevel=0.035)
    box("Shin shell", (x, 0, 0.32), (0.135, 0.15, 0.38), white, bevel=0.04)
    joint("Knee", (x, 0, 0.55), 0.08)
    box("Knee cap", (x, -0.071, 0.55), (0.12, 0.045, 0.11), metal, bevel=0.025)
    box("Thigh shell", (x, 0, 0.77), (0.17, 0.19, 0.34), white, bevel=0.055)
    joint("Hip", (x, 0, 0.96), 0.095)
box("Pelvis", (0, 0, 1.00), (0.34, 0.22, 0.17), black, bevel=0.055)
box("Abdominal core", (0, 0, 1.145), (0.25, 0.17, 0.18), black, bevel=0.03)
for z in [1.09, 1.14, 1.19]:
    box("Abdominal rib", (0, -0.095, z), (0.25, 0.025, 0.022), metal, bevel=0.008)
box("Thorax shell", (0, 0, 1.365), (0.43, 0.26, 0.33), white, bevel=0.075)
box("Back service spine", (0, 0.145, 1.35), (0.13, 0.06, 0.31), black)
box("Collar", (0, -0.03, 1.525), (0.24, 0.20, 0.065), white, bevel=0.025)
joint("Neck", (0, 0, 1.57), 0.067)
box("Head shell", (0, 0, 1.69), (0.22, 0.20, 0.22), white, bevel=0.07)
box("Black face visor", (0, -0.095, 1.695), (0.194, 0.043, 0.155), visor, bevel=0.04)
box("Face status line", (0, -0.12, 1.68), (0.105, 0.008, 0.008), teal, bevel=0.003)
for x in [-0.06, 0.06]:
    joint("Optical sensor", (x, -0.117, 1.72), 0.011)
# Decal plane with explicit unmirrored UVs.
mesh = bpy.data.meshes.new("Chest badge UV")
mesh.from_pydata(
    [
        (-0.115, -0.134, 1.27),
        (0.115, -0.134, 1.27),
        (0.115, -0.134, 1.50),
        (-0.115, -0.134, 1.50),
    ],
    [],
    [(0, 1, 2, 3)],
)
mesh.materials.append(badge)
uv = mesh.uv_layers.new(name="UVMap")
for i, co in enumerate([(0, 0), (1, 0), (1, 1), (0, 1)]):
    uv.data[i].uv = co
obj = bpy.data.objects.new("CB_Chest_Badge", mesh)
bpy.context.collection.objects.link(obj)
parent(obj, root)
for side, name in [(-1, "Shoulder_L"), (1, "Shoulder_R")]:
    x = side * 0.285
    pivot = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(pivot)
    pivot.location = (x, 0, 1.445)
    parent(pivot, root)
    joint("Shoulder actuator", (x, 0, 1.445), 0.085, pivot)
    box("Shoulder cover", (x, 0, 1.47), (0.17, 0.20, 0.16), white, pivot, 0.055)
    box("Upper arm", (x, 0, 1.26), (0.125, 0.14, 0.25), white, pivot, 0.04)
    joint("Elbow", (x, 0, 1.085), 0.065, pivot)
    box("Forearm", (x, -0.012, 0.93), (0.12, 0.145, 0.22), white, pivot, 0.04)
    box("Wrist", (x, -0.01, 0.79), (0.075, 0.075, 0.065), metal, pivot, 0.015)
    box("Palm", (x, -0.018, 0.71), (0.105, 0.055, 0.105), black, pivot, 0.022)
    for finger in range(4):
        fx = x + (finger - 1.5) * 0.024
        box("Finger", (fx, -0.027, 0.627), (0.018, 0.035, 0.07), white, pivot, 0.008)
    box(
        "Thumb",
        (x - side * 0.067, -0.025, 0.69),
        (0.028, 0.045, 0.072),
        white,
        pivot,
        0.01,
    )
    box(
        "Forearm service stripe",
        (x, -0.09, 0.95),
        (0.07, 0.014, 0.015),
        teal,
        pivot,
        0.005,
    )
# Verify that rotating a shoulder cannot move its actuator away from the socket.
bpy.context.view_layer.update()
for name in ["Shoulder_L", "Shoulder_R"]:
    shoulder = bpy.data.objects[name]
    assert abs(shoulder.location.z - 1.445) < 1e-6
    actuator = next(
        o for o in shoulder.children if o.name.startswith("Shoulder actuator")
    )
    socket = shoulder.matrix_world.translation.copy()
    for angle in [0, -0.55, -1.4]:
        shoulder.rotation_euler.x = angle
        bpy.context.view_layer.update()
        assert (actuator.matrix_world.translation - socket).length < 1e-5
    shoulder.rotation_euler.x = 0
bpy.context.view_layer.update()
# Export model only, before adding studio props.
bpy.ops.object.select_all(action="DESELECT")
for o in [root] + list(root.children_recursive):
    o.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(
    filepath=str(ROOT / "godot/assets/cb-robot.glb"),
    export_format="GLB",
    use_selection=True,
)
bpy.context.view_layer.update()
points = [
    o.matrix_world @ Vector(v)
    for o in root.children_recursive
    if o.type == "MESH"
    for v in o.bound_box
]
height = max(v.z for v in points) - min(v.z for v in points)
assert abs(height - 1.8) < 0.005, height
print("CB_ROBOT_HEIGHT_M:", height)
# Studio preview with the same original model.
box(
    "Studio floor",
    (0, 0, -0.045),
    (200, 200, 0.08),
    material("Studio blue", (0.075, 0.12, 0.16)),
    bevel=0.01,
)
bpy.ops.object.camera_add(location=(2.5, -4.6, 2.1))
cam = bpy.context.object
cam.rotation_euler = (
    (Vector((0, 0, 0.94)) - cam.location).to_track_quat("-Z", "Y").to_euler()
)
cam.data.type = "ORTHO"
cam.data.ortho_scale = 2.35
scene.camera = cam
for at, energy, size in [
    ((1, -3, 4), 450, 4),
    ((-3, -1, 2), 260, 3),
    ((1, 2, 3), 500, 2),
]:
    bpy.ops.object.light_add(type="AREA", location=at)
    o = bpy.context.object
    o.data.energy = energy
    o.data.shape = "DISK"
    o.data.size = size
    o.rotation_euler = (
        (Vector((0, 0, 1)) - o.location).to_track_quat("-Z", "Y").to_euler()
    )
scene.world.color = (0.15, 0.18, 0.22)
scene.render.engine = "CYCLES"
scene.cycles.samples = 32
scene.render.resolution_x = 900
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.render.filepath = str(ROOT / "blender/cb-robot-preview.png")
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "blender/cb_robot.blend"))
bpy.ops.render.render(write_still=True)
