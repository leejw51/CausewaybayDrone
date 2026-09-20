import bpy, math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def mat(name, color, rough=0.65):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (
        *color,
        1,
    )
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = rough
    return m


bread = mat("Golden wholegrain crust", (0.67, 0.34, 0.11))
crumb = mat("Soft bread", (0.94, 0.79, 0.48))
green = mat("Fresh lettuce", (0.15, 0.42, 0.045))
red = mat("Tomato", (0.75, 0.07, 0.035))
cheese = mat("Cheddar", (0.98, 0.59, 0.06))
paper = mat("Ivory paper", (0.93, 0.88, 0.73))
brown = mat("Kraft sleeve", (0.43, 0.23, 0.10))
dark = mat("Charcoal lid", (0.025, 0.035, 0.03), 0.3)
teal = mat("COAST teal", (0.025, 0.32, 0.28))


def finish(obj, name, material):
    obj.name = name
    obj.data.materials.append(material)
    return obj


sand = []
coffee = []


def triangle(name, z, thick, scale, material):
    pts = [(-0.125, -0.095), (0.125, -0.095), (-0.125, 0.13)]
    v = [(x * scale, y * scale, h) for h in [z, z + thick] for x, y in pts]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(
        v, [], [(2, 1, 0), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)]
    )
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    finish(obj, name, material)
    bevel = obj.modifiers.new("Soft food edges", "BEVEL")
    bevel.width = 0.003
    bevel.segments = 3
    sand.append(obj)


triangle("Bottom crust", 0.006, 0.018, 1, bread)
triangle("Bottom soft bread", 0.024, 0.013, 0.98, crumb)
triangle("Cheddar slice", 0.037, 0.006, 1.06, cheese)
triangle("Lettuce leaf", 0.044, 0.008, 1.09, green)
triangle("Tomato filling", 0.052, 0.012, 0.92, red)
triangle("Top soft bread", 0.064, 0.013, 0.98, crumb)
triangle("Top golden crust", 0.077, 0.018, 1, bread)
# Small toasted seed dots on top.
for x, y in [
    (-0.08, -0.06),
    (-0.02, -0.05),
    (0.045, -0.065),
    (-0.085, 0.01),
    (-0.04, 0.015),
    (-0.09, 0.075),
]:
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=10, ring_count=6, radius=1, location=(x, y, 0.095)
    )
    o = finish(bpy.context.object, "Toasted grain", bread)
    o.scale = (0.003, 0.006, 0.0015)
    sand.append(o)


def cyl(name, z, radius, depth, material, top=None):
    bpy.ops.mesh.primitive_cone_add(
        vertices=48,
        radius1=radius,
        radius2=top if top is not None else radius,
        depth=depth,
        location=(0.38, 0, z),
    )
    o = finish(bpy.context.object, name, material)
    coffee.append(o)
    bevel = o.modifiers.new("Rounded rim", "BEVEL")
    bevel.width = 0.0015
    bevel.segments = 3
    return o


cyl("Paper coffee cup", 0.073, 0.032, 0.146, paper, 0.046)
cyl("Kraft insulating sleeve", 0.072, 0.038, 0.053, brown, 0.043)
cyl("Lid seal", 0.15, 0.049, 0.009, dark)
cyl("Raised sip lid", 0.157, 0.044, 0.012, dark, 0.041)
bpy.ops.mesh.primitive_torus_add(
    major_radius=0.038,
    minor_radius=0.002,
    major_segments=48,
    minor_segments=10,
    location=(0.38, 0, 0.164),
)
coffee.append(finish(bpy.context.object, "Lid drinking rim", dark))
bpy.ops.mesh.primitive_cube_add(size=1, location=(0.38, -0.024, 0.165))
o = finish(bpy.context.object, "Sip opening", brown)
o.scale = (0.015, 0.006, 0.001)
coffee.append(o)
bpy.ops.object.text_add(location=(0.38, -0.043, 0.07), rotation=(math.pi / 2, 0, 0))
o = bpy.context.object
o.name = "COAST coffee label"
o.data.body = "COAST"
o.data.align_x = "CENTER"
o.data.size = 0.012
o.data.extrude = 0.0002
o.data.materials.append(teal)
bpy.ops.object.convert(target="MESH")
coffee.append(bpy.context.object)


def export(objects, name, shift=0):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
        o.location.x -= shift
    bpy.ops.export_scene.gltf(
        filepath=str(ROOT / "godot/assets" / name),
        export_format="GLB",
        use_selection=True,
    )
    for o in objects:
        o.location.x += shift


export(sand, "sandwich.glb")
export(coffee, "coffee.glb", 0.38)
# Product studio, saved only in the editable Blender file.
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.003))
finish(bpy.context.object, "Studio floor", mat("Studio cream", (0.65, 0.72, 0.68)))
bpy.ops.object.light_add(type="AREA", location=(0.2, -0.5, 1.5))
bpy.context.object.data.energy = 70
bpy.context.object.data.shape = "DISK"
bpy.context.object.data.size = 1.2
bpy.ops.object.camera_add(location=(0.70, -0.90, 0.65))
cam = bpy.context.object
direction = __import__("mathutils").Vector((0.16, 0, 0.07)) - cam.location
cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
cam.data.type = "ORTHO"
cam.data.ortho_scale = 0.85
bpy.context.scene.camera = cam
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 32
scene.render.resolution_x = 1000
scene.render.resolution_y = 700
scene.render.resolution_percentage = 100
scene.world.color = (0.3, 0.3, 0.3)
scene.render.filepath = str(ROOT / "blender/food-preview.png")
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "blender/delivery_food.blend"))
bpy.ops.render.render(write_still=True)
