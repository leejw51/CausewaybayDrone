"""Alex, Mei and Chef Bo: rounded 3D interpretations of CausewaybayGolang sprites."""

from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
base = (
    (ROOT / "blender/tools/build_rust_coder.py").read_text().split("objects = list")[0]
)
# The unformatted original spelling is also accepted.
base = base.split("objects=list")[0]
for name, color in [
    ("Alex", (0.035, 0.10, 0.23)),
    ("Mei", (0.95, 0.55, 0.035)),
    ("Chef_Bo", (0.90, 0.88, 0.80)),
]:
    exec(compile(base, str(ROOT / "blender/tools/build_rust_coder.py"), "exec"))
    orange.diffuse_color = (*color, 1)
    orange.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (
        *color,
        1,
    )
    for o in list(bpy.context.scene.objects):
        if any(
            o.name.startswith(n)
            for n in [
                "Field laptop",
                "Laptop screen",
                "Screen display",
                "CB chest patch",
            ]
        ):
            bpy.data.objects.remove(o, do_unlink=True)
    if name == "Alex":
        box(
            "Backpack",
            (0, 0.23, 1.08),
            (0.39, 0.20, 0.44),
            mat("Tan canvas", (0.45, 0.25, 0.10)),
        )
    if name == "Mei":
        ball("Long hair", (0, 0.14, 1.40), (0.23, 0.14, 0.32), hair)
        box(
            "Pink hair clip",
            (0.16, -0.16, 1.72),
            (0.11, 0.035, 0.035),
            mat("Pink", (0.8, 0.06, 0.28)),
        )
        for o in list(bpy.context.scene.objects):
            if o.name.startswith("Glasses"):
                bpy.data.objects.remove(o, do_unlink=True)
    if name == "Chef_Bo":
        box("Apron", (0, -0.175, 1.0), (0.40, 0.035, 0.50), white)
        box("Hat band", (0, 0, 1.79), (0.36, 0.29, 0.10), white)
        for x in [-0.12, 0, 0.12]:
            ball("Chef toque", (x, 0, 1.89), (0.13, 0.16, 0.14), white)
    for x in [-0.10, 0.10]:
        ball("Eye white", (x, -0.196, 1.56), (0.06, 0.022, 0.055), white)
        ball("Pupil", (x, -0.218, 1.56), (0.025, 0.012, 0.035), hair)
    box("Smile", (0, -0.197, 1.435), (0.075, 0.014, 0.016), hair)
    head = bpy.data.objects.new("HeadPivot", None)
    bpy.context.collection.objects.link(head)
    head.location = (0, 0, 1.34)
    for obj in list(bpy.context.scene.objects):
        if obj == head:
            continue
        if any(
            obj.name.startswith(n)
            for n in [
                "Head",
                "Hair",
                "Long hair",
                "Pink hair",
                "Glasses",
                "Eye",
                "Pupil",
                "Smile",
                "Hat band",
                "Chef toque",
            ]
        ):
            bpy.context.view_layer.update()
            matrix = obj.matrix_world.copy()
            obj.parent = head
            obj.matrix_world = matrix
    # Articulated legs: knee and hip pivots, without a full skinning rig.
    for obj in list(bpy.context.scene.objects):
        if obj.name.startswith("Trousers"):
            bpy.data.objects.remove(obj, do_unlink=True)
    for side in [-1, 1]:
        suffix = "_L" if side < 0 else "_R"
        thigh = box("Thigh" + suffix, (side * 0.12, 0, 0.59), (0.19, 0.22, 0.30), dark)
        shin = box("Shin" + suffix, (side * 0.12, 0, 0.29), (0.18, 0.21, 0.30), dark)
        for kind, z, names in [
            ("Leg", 0.75, ["Thigh", "Shin", "Sneaker"]),
            ("Arm", 1.26, ["Sleeve", "Hand"]),
        ]:
            pivot = bpy.data.objects.new(kind + suffix, None)
            bpy.context.collection.objects.link(pivot)
            pivot.location = (side * (0.12 if kind == "Leg" else 0.32), 0, z)
            for obj in list(bpy.context.scene.objects):
                if (
                    any(obj.name.startswith(n) for n in names)
                    and obj.location.x * side > 0
                ):
                    bpy.context.view_layer.update()
                    matrix = obj.matrix_world.copy()
                    obj.parent = pivot
                    obj.matrix_world = matrix
            if kind == "Leg":
                knee = bpy.data.objects.new("Knee" + suffix, None)
                bpy.context.collection.objects.link(knee)
                knee.location = (side * 0.12, 0, 0.44)
                bpy.context.view_layer.update()
                matrix = knee.matrix_world.copy()
                knee.parent = pivot
                knee.matrix_world = matrix
                for obj in list(pivot.children):
                    if obj.name.startswith("Shin") or obj.name.startswith("Sneaker"):
                        bpy.context.view_layer.update()
                        matrix = obj.matrix_world.copy()
                        obj.parent = knee
                        obj.matrix_world = matrix
    bpy.ops.export_scene.gltf(
        filepath=str(ROOT / f"godot/assets/{name.lower()}.glb"),
        export_format="GLB",
        export_apply=True,
    )
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / f"blender/{name.lower()}.blend"))
