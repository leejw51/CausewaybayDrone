"""Raiden-inspired field engineer and an original rendered title backdrop."""

from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
s = bpy.context.scene
s.unit_settings.system = "METRIC"


def mat(name, color):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Roughness"].default_value = 0.4
    return m


orange = mat("Rust orange hoodie", (0.65, 0.16, 0.035))
dark = mat("Ink navy", (0.025, 0.05, 0.075))
skin = mat("Warm skin", (0.68, 0.40, 0.24))
hair = mat("Black hair", (0.016, 0.019, 0.025))
teal = mat("Telemetry teal", (0.025, 0.65, 0.57))
white = mat("Warm white", (0.85, 0.88, 0.81))


def box(name, p, size, m):
    bpy.ops.mesh.primitive_cube_add(size=1, location=p)
    o = bpy.context.object
    o.name = name
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(m)
    b = o.modifiers.new("Rounded silhouette", "BEVEL")
    b.width = min(size) * 0.22
    b.segments = 4
    o.modifiers.new("Normals", "WEIGHTED_NORMAL")
    return o


def ball(name, p, size, m):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=24, ring_count=16, radius=1, location=p
    )
    o = bpy.context.object
    o.name = name
    o.scale = size
    o.data.materials.append(m)
    for f in o.data.polygons:
        f.use_smooth = True
    return o


for x in [-0.12, 0.12]:
    box("Sneaker", (x, -0.06, 0.075), (0.19, 0.33, 0.15), white)
    box("Trousers", (x, 0, 0.43), (0.19, 0.22, 0.64), dark)
box("Hoodie", (0, 0, 1.04), (0.51, 0.30, 0.64), orange)
ball("Hood", (0, 0.10, 1.30), (0.27, 0.19, 0.20), orange)
ball("Head", (0, -0.025, 1.53), (0.21, 0.18, 0.25), skin)
ball("Hair", (0, 0.012, 1.67), (0.216, 0.18, 0.15), hair)
for x in [-0.105, 0.105]:
    box("Glasses", (x, -0.192, 1.565), (0.18, 0.036, 0.095), dark)
box("Glasses bridge", (0, -0.203, 1.565), (0.06, 0.025, 0.018), dark)
for x in [-0.32, 0.32]:
    box("Sleeve", (x, -0.045, 1.06), (0.17, 0.22, 0.42), orange)
    ball("Hand", (x, -0.24, 0.965), (0.08, 0.10, 0.075), skin)
box("Field laptop", (0, -0.29, 0.94), (0.56, 0.37, 0.045), dark)
box("Laptop screen", (0, -0.46, 1.08), (0.54, 0.035, 0.28), dark)
box("Screen display", (0, -0.438, 1.08), (0.48, 0.012, 0.22), teal)
box("CB chest patch", (-0.13, -0.157, 1.20), (0.10, 0.016, 0.08), white)
objects = list(bpy.context.scene.objects)
root = bpy.data.objects.new("Causewaybay_Rust_Coder", None)
bpy.context.collection.objects.link(root)
for o in objects:
    o.parent = root
root["role"] = "AI drone developer / Olympic Park field trial operator"
bpy.ops.export_scene.gltf(
    filepath=str(ROOT / "godot/assets/rust-coder.glb"), export_format="GLB"
)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "blender/rust_coder.blend"))
# Compose a title stage with reserved negative space for live UI typography.
root.location = (2, 0, 0)
ground = mat("Title midnight stage", (0.015, 0.06, 0.085))
box("Stage", (0, 0, -0.15), (200, 200, 0.2), ground)
for x in [1.25, 2.75]:
    for y in [0.55, 1.85]:
        box("Rotor arm", (x, y, 1.8), (0.1, 0.65, 0.07), dark)
        ball("Rotor hub", (x, y, 1.85), (0.16, 0.16, 0.065), teal)
        box("Propeller", (x, y, 1.90), (0.57, 0.055, 0.025), dark)
box("Trial drone", (2, 1.2, 1.8), (1.05, 0.70, 0.3), white)
box("Drone face", (2, 0.835, 1.8), (0.5, 0.025, 0.16), dark)
for x in [1.86, 2.14]:
    ball("Friendly eye", (x, 0.811, 1.81), (0.035, 0.018, 0.035), teal)
box("Delivery pod", (2, 1.2, 1.50), (0.50, 0.48, 0.25), orange)
for x, y in [(3.5, 3), (0, 4), (4, 5), (-3, 6)]:
    box("Tree trunk", (x, y, 0.6), (0.18, 0.18, 1.2), orange)
    ball("Tree crown", (x, y, 1.65), (0.8, 0.65, 1.1), teal)
bpy.ops.object.camera_add(location=(5, -9, 4.1))
cam = bpy.context.object
cam.rotation_euler = (
    (Vector((0.1, 0.6, 1)) - cam.location).to_track_quat("-Z", "Y").to_euler()
)
cam.data.type = "ORTHO"
cam.data.ortho_scale = 7.8
s.camera = cam
for p, power, size in [((1, -4, 6), 1100, 7), ((4, 3, 5), 1400, 5)]:
    bpy.ops.object.light_add(type="AREA", location=p)
    o = bpy.context.object
    o.data.energy = power
    o.data.shape = "DISK"
    o.data.size = size
    o.rotation_euler = (
        (Vector((1, 0, 1)) - o.location).to_track_quat("-Z", "Y").to_euler()
    )
s.world.color = (0.1, 0.14, 0.2)
s.render.engine = "CYCLES"
s.cycles.samples = 24
s.render.resolution_x = 1600
s.render.resolution_y = 900
s.render.resolution_percentage = 100
s.render.filepath = str(ROOT / "godot/assets/title-field-trial.png")
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "blender/title_field_trial.blend"))
bpy.ops.render.render(write_still=True)
