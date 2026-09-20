"""Stylized park furnishings aligned to mapped paths, explicitly artistic placements.
Executed by build_park_environment.py in its Blender namespace.
"""


def ground(x, z):
    fx = max(0, min((x - t["x"]) / t["step"], t["nx"] - 1.001))
    fz = max(0, min((z - t["z"]) / t["step"], t["nz"] - 1.001))
    ix, iz = int(fx), int(fz)
    u, v = fx - ix, fz - iz
    n = t["nx"]
    h = t["heights"]
    a, b, c, d = (
        h[iz * n + ix],
        h[iz * n + ix + 1],
        h[(iz + 1) * n + ix],
        h[(iz + 1) * n + ix + 1],
    )
    return (
        a + (b - a) * u + (c - a) * v
        if u + v <= 1
        else d + (c - d) * (1 - u) + (b - d) * (1 - v)
    )


def inside(x, z, ring):
    result = False
    for a, b in zip(ring, ring[1:] + ring[:1]):
        if (a[1] > z) != (b[1] > z) and x < (b[0] - a[0]) * (z - a[1]) / (
            b[1] - a[1]
        ) + a[0]:
            result = not result
    return result


blocked = [f["rings"][0] for f in data["buildings"] + data["water"]]
occupied = []
placements = []
decor = []
bench_count = 0
flower_count = 0
flowerbed_count = 0
wood = material("Storybook warm timber", (0.35, 0.17, 0.065), roughness=0.45)
stone = material("Storybook rounded stone", (0.37, 0.45, 0.43), roughness=0.6)
leaf_mats = [
    material("Garden leaf " + str(i), c, roughness=0.42)
    for i, c in enumerate(
        [(0.095, 0.30, 0.055), (0.16, 0.42, 0.075), (0.29, 0.52, 0.11)]
    )
]
petals = [
    material("Petal " + str(i), c, roughness=0.42)
    for i, c in enumerate([(0.88, 0.45, 0.24), (0.94, 0.70, 0.16), (0.55, 0.28, 0.66)])
]
cream = material("Garden ceramic", (0.8, 0.69, 0.48), roughness=0.42)


# Dressing props are background geometry at metre scale, so they are tessellated
# only as finely as smooth shading needs. Centimetre-sized flower parts use the
# coarse preset; everything merges into one mesh, so segments cost repository size.
SMOOTH_OVAL = (8, 6)
COARSE_OVAL = (6, 4)


def oval(name, at, size, mat, detail=SMOOTH_OVAL):
    segments, ring_count = detail
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=ring_count, radius=1, location=at
    )
    o = bpy.context.object
    o.name = name
    o.scale = size
    o.data.materials.append(mat)
    for f in o.data.polygons:
        f.use_smooth = True
    decor.append(o)
    return o


def rounded(name, at, size, mat, angle=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    o = bpy.context.object
    o.name = name
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.rotation_euler.z = angle
    o.data.materials.append(mat)
    b = o.modifiers.new("Soft edges", "BEVEL")
    b.width = min(size) * 0.22
    b.segments = 2
    bpy.ops.object.modifier_apply(modifier=b.name)
    o.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    bpy.ops.object.modifier_apply(modifier=o.modifiers[0].name)
    decor.append(o)
    return o


# Build three shared flower meshes once; instances keep the exported scene compact.
flower_meshes = []
for color in petals:
    start = len(decor)
    rounded("Flower stem", (0, 0, 0.22), (0.025, 0.025, 0.44), leaf_mats[0])
    oval(
        "Flower leaf", (0.08, 0, 0.16), (0.12, 0.045, 0.035), leaf_mats[1], COARSE_OVAL
    )
    for j in range(6):
        theta = j * math.tau / 6
        oval(
            "Flower petal",
            (0.115 * math.cos(theta), 0.115 * math.sin(theta), 0.44),
            (0.10, 0.075, 0.045),
            color,
            COARSE_OVAL,
        )
    oval(
        "Golden flower center",
        (0, 0, 0.475),
        (0.065, 0.065, 0.035),
        petals[1],
        COARSE_OVAL,
    )
    bpy.ops.object.select_all(action="DESELECT")
    parts = decor[start:]
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    prototype = bpy.context.object
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    flower_meshes.append(prototype.data)
    del decor[start:]
    bpy.data.objects.remove(prototype, do_unlink=True)


def flower(x, z, variant):
    global flower_count
    obj = bpy.data.objects.new("Pathside daisy", flower_meshes[variant % 3])
    bpy.context.collection.objects.link(obj)
    obj.location = (x, -z, ground(x, z) + 0.025)
    obj.rotation_euler.z = variant * 2.4
    obj.scale = (1, 1, 0.85 + (variant % 4) * 0.10)
    decor.append(obj)
    flower_count += 1


for road in data["roads"]:
    if not road.get("inside_park") or road["kind"] not in [
        "footway",
        "path",
        "pedestrian",
    ]:
        continue
    points = road["points"]
    for i in range(1, len(points), 5):
        a, b = points[i - 1], points[i]
        dx, dz = b[0] - a[0], b[2] - a[2]
        length = math.hypot(dx, dz)
        if length < 0.1:
            continue
        x, z = (
            b[0] - dz / length * (road["width"] / 2 + 5),
            b[2] + dx / length * (road["width"] / 2 + 5),
        )
        if (x - 440.508) ** 2 + (z + 491.397) ** 2 < 95**2:
            continue
        if any((x - px) ** 2 + (z - pz) ** 2 < 24**2 for px, pz in occupied):
            continue
        ix = int((x - t["x"]) / t["step"])
        iz = int((z - t["z"]) / t["step"])
        if (
            not (0 <= ix < t["nx"] and 0 <= iz < t["nz"])
            or t["colors"][iz * t["nx"] + ix] != 1
        ):
            continue
        if any(inside(x, z, r) for r in blocked):
            continue
        occupied.append((x, z))
        h = ground(x, z)
        k = len(occupied)
        placements.append(
            {
                "position": [x, h, z],
                "source_road": road.get("id"),
                "placement": "artistic path-side dressing, not surveyed vegetation",
            }
        )
        height = 4.5 + (k % 4) * 0.45
        bpy.ops.mesh.primitive_cone_add(
            vertices=12,
            radius1=0.21,
            radius2=0.13,
            depth=height * 0.65,
            location=(x, -z, h + height * 0.325),
        )
        trunk_obj = bpy.context.object
        trunk_obj.name = "Garden trunk"
        trunk_obj.data.materials.append(wood)
        decor.append(trunk_obj)
        for cx, cy, cz, radius in [
            (-0.6, 0, 0.64, 0.30),
            (0.6, 0.15, 0.70, 0.29),
            (0, -0.3, 0.86, 0.31),
        ]:
            oval(
                "Soft garden canopy",
                (x + cx, -z + cy, h + height * cz),
                (height * radius, height * radius * 0.9, height * radius),
                leaf_mats[k % 3],
            )
        if k % 3 == 0:
            for j in range(3):
                oval(
                    "Low garden shrub",
                    (x + 2.6 + j * 0.65, -z + 0.8, h + 0.45),
                    (0.7, 0.65, 0.58),
                    leaf_mats[(k + j) % 3],
                )
        if k % 4 == 0:
            angle = math.atan2(-dz, dx)
            # Bench sits beside its tree, with feet independently sampled on the terrain.
            bx, bz = x + dx / length * 3, z + dz / length * 3
            bh = ground(bx, bz)
            # A 1.8 m timber bench: separate slats, backrest and rounded armrests.
            bench_count += 1

            def bench_part(name, along, across, height, size, mat):
                return rounded(
                    name,
                    (
                        bx + math.cos(angle) * along - math.sin(angle) * across,
                        -bz + math.sin(angle) * along + math.cos(angle) * across,
                        bh + height,
                    ),
                    size,
                    mat,
                    angle,
                )

            for row in range(4):
                bench_part(
                    "Timber seat slat",
                    0,
                    -0.18 + row * 0.12,
                    0.48,
                    (1.8, 0.105, 0.065),
                    wood,
                )
            for row in range(3):
                bench_part(
                    "Timber back slat",
                    0,
                    -0.24,
                    0.70 + row * 0.12,
                    (1.8, 0.065, 0.09),
                    wood,
                )
            for sign in [-1, 1]:
                for across in [-0.18, 0.18]:
                    lx = bx + math.cos(angle) * sign * 0.69 - math.sin(angle) * across
                    lz = bz - math.sin(angle) * sign * 0.69 - math.cos(angle) * across
                    foot = ground(lx, lz) - 0.025
                    height = max(0.12, bh + 0.47 - foot)
                    rounded(
                        "Bench anchored leg",
                        (lx, -lz, foot + height / 2),
                        (0.065, 0.065, height),
                        stone,
                        angle,
                    )
                bench_part(
                    "Bench back support",
                    sign * 0.69,
                    -0.24,
                    0.67,
                    (0.055, 0.065, 0.62),
                    stone,
                )
                bench_part(
                    "Bench armrest", sign * 0.82, 0, 0.70, (0.09, 0.52, 0.075), wood
                )
                bench_part(
                    "Arm support", sign * 0.82, 0.16, 0.59, (0.055, 0.055, 0.20), stone
                )
            # Two low flower borders flank the seat, leaving its approach open.
            for side in [-1, 1]:
                cx = bx + math.cos(angle) * side * 1.65
                cz = bz - math.sin(angle) * side * 1.65
                if any(inside(cx, cz, ring) for ring in blocked):
                    continue
                flowerbed_count += 1
                for j in range(9):
                    along = (j % 3 - 1) * 0.30
                    across = (j // 3 - 1) * 0.32
                    fx = cx + math.cos(angle) * along - math.sin(angle) * across
                    fz = cz - math.sin(angle) * along - math.cos(angle) * across
                    flower(fx, fz, k + j)
                for j in range(8):
                    theta = j * math.tau / 8
                    rx, rz = cx + math.cos(theta) * 0.65, cz + math.sin(theta) * 0.65
                    oval(
                        "Flowerbed pebble edging",
                        (rx, -rz, ground(rx, rz) + 0.06),
                        (0.14, 0.11, 0.09),
                        cream,
                    )
        if k % 5 == 0:
            for j in range(3):
                rx, rz = x - 2.8 - j * 0.5, z + 0.5
                oval(
                    "Soft stone",
                    (rx, -rz, ground(rx, rz) + 0.17),
                    (0.5 - j * 0.08, 0.38, 0.29),
                    stone,
                )
        if len(occupied) >= 180:
            break
    if len(occupied) >= 180:
        break
# Merge shared-material geometry: compact scene, not hundreds of runtime draw calls.
bpy.ops.object.select_all(action="DESELECT")
for obj in decor:
    obj.select_set(True)
if decor:
    bpy.context.view_layer.objects.active = decor[0]
    bpy.ops.object.join()
    dressing = bpy.context.object
    dressing.name = "Designed park path furnishings"
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.ops.export_scene.gltf(
        filepath=str(ROOT / "godot/assets/park-dressing.glb"),
        export_format="GLB",
        use_selection=True,
        # Every dressing material is a flat base color; UVs would be dead weight.
        export_texcoords=False,
    )
(ROOT / "godot/data/park-dressing.json").write_text(
    json.dumps(
        {
            "accuracy": "Art-directed dressing; base paths, coordinates and terrain come from real-map.json. Not a surveyed tree or bench inventory.",
            "tree_count": len(placements),
            "bench_count": bench_count,
            "flowerbed_count": flowerbed_count,
            "flower_count": flower_count,
            "placements": placements,
        },
        indent=2,
    )
)
print("PARK_DRESSING_READY:", len(placements), "tree groups")
