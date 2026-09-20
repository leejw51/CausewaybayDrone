"""Independent geographic audit; source consistency is not survey accuracy.
Run with Pillow and pyproj. No network, no changes to map geometry.
"""

import json, math, hashlib, statistics
from pathlib import Path
from collections import Counter
from PIL import Image
from pyproj import Geod

ROOT = Path(__file__).resolve().parents[1]
data = json.loads((ROOT / "godot/data/real-map.json").read_text())
t = data["terrain"]
o = data["origin"]
scope = json.loads((ROOT / "godot/data/park-scope.json").read_text())
geod = Geod(ellps="WGS84")
tiles = {}
for f in (ROOT / "godot/data/elevation").glob("14-*.png"):
    _, x, y = f.stem.split("-")
    tiles[int(x), int(y)] = Image.open(f).convert("RGB")


def raw(lat, lon):
    x = (lon + 180) / 360 * 2**22
    y = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * 2**22
    ix, iy = math.floor(x), math.floor(y)
    u, v = x - ix, y - iy

    def pixel(x, y):
        tile = tiles.get((x // 256, y // 256))
        if tile is None:
            raise ValueError(f"Missing source tile {x // 256},{y // 256}")
        r, g, b = tile.getpixel((x % 256, y % 256))
        return 256 * r + g + b / 256 - 32768

    return sum(
        pixel(ix + dx, iy + dy) * wx * wy
        for dx, wx in [(0, 1 - u), (1, u)]
        for dy, wy in [(0, 1 - v), (1, v)]
    )


def ground(x, z):
    fx = min(max((x - t["x"]) / t["step"], 0), t["nx"] - 1)
    fz = min(max((z - t["z"]) / t["step"], 0), t["nz"] - 1)
    ix = min(int(fx), t["nx"] - 2)
    iz = min(int(fz), t["nz"] - 2)
    u, v = fx - ix, fz - iz
    n = t["nx"]
    i = iz * n + ix
    a, b, c, d = [t["heights"][k] for k in [i, i + 1, i + n, i + n + 1]]
    return (
        a + (b - a) * u + (c - a) * v
        if u + v <= 1
        else d + (c - d) * (1 - u) + (b - d) * (1 - v)
    )


def inside(x, z, ring):
    hit = False
    for a, b in zip(ring, ring[1:] + ring[:1]):
        if (a[1] > z) != (b[1] > z) and x < (b[0] - a[0]) * (z - a[1]) / (
            b[1] - a[1]
        ) + a[0]:
            hit = not hit
    return hit


rows = []
for p in data["landmarks"]:
    az, _, distance = geod.inv(o["lon"], o["lat"], p["lon"], p["lat"])
    x, _, z = p["position"]
    projected = math.hypot(x, z)
    rows.append(
        {
            "name": p["name"],
            "latitude": p["lat"],
            "longitude": p["lon"],
            "geodesic_distance_m": distance,
            "projection_error_m": abs(distance - projected),
            "rendered_dem_altitude_m": ground(x, z) + o["elevation_datum"],
            "height_source": p.get("height_source", "unspecified"),
        }
    )
errors = []
nearest_errors = []
samples = []
for iz in range(0, t["nz"] - 1, 2):
    for ix in range(0, t["nx"] - 1, 2):
        x = t["x"] + (ix + 0.37) * t["step"]
        z = t["z"] + (iz + 0.41) * t["step"]
        if not any(
            inside(x, z, p[0]) and not any(inside(x, z, h) for h in p[1:])
            for p in scope["park_polygons"]
        ):
            continue
        # Exclude water and neighboring cells affected by intentional waterbed leveling.
        if any(
            inside(x + dx, z + dz, w["rings"][0])
            for w in data["water"]
            for dx, dz in [(0, 0), (-15, 0), (15, 0), (0, -15), (0, 15)]
        ):
            continue
        lat = o["lat"] - z / o["metres_per_lat_degree"]
        lon = o["lon"] + x / o["metres_per_lon_degree"]
        scene = ground(x, z)
        residual = scene + o["elevation_datum"] - raw(lat, lon)
        errors.append(residual)
        nearest_errors.append(scene - t["heights"][iz * t["nx"] + ix])
        samples.append([x, z, residual])


def metrics(values):
    return {
        "samples": len(values),
        "mean_m": statistics.mean(values),
        "rmse_m": math.sqrt(statistics.mean(v * v for v in values)),
        "max_abs_m": max(map(abs, values)),
    }


report = {
    "survey_accuracy": "NOT VERIFIED: no independent surveyed ground control or local high-resolution DEM supplied",
    "coordinate_system": "Local WGS84 metre-scale tangent approximation; +X east, -Z north",
    "landmarks": rows,
    "dem_mesh_vs_source": metrics(errors),
    "old_backend_nearest_vertex_vs_rendered": metrics(nearest_errors),
    "visible_building_heights": dict(
        Counter(
            data["buildings"][i]["height_source"]
            for i in scope["visible_building_indices"]
        )
    ),
    "source_sha256": {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest()
        for p in (ROOT / "godot/data/elevation").glob("*.png")
    },
    "official_reference": "https://www.ksponco.or.kr/olympicpark/map",
    "high_resolution_data_provider": "https://map.ngii.go.kr/ms/map/NlipMap.do?menu=emap",
}
(ROOT / "docs/geography-audit.json").write_text(json.dumps(report, indent=2))
lines = [
    "# Olympic Park geographic audit",
    "",
    report["survey_accuracy"],
    "",
    "This audit checks numerical conversion and model consistency, not agreement with surveyed reality. Waterbed modification areas are excluded from the DEM comparison.",
    "",
    "| Landmark | Projection distance error (m) | DEM altitude (m) |",
    "|---|---:|---:|",
]
for p in rows:
    lines.append(
        f"| {p['name']} | {p['projection_error_m']:.4f} | {p['rendered_dem_altitude_m']:.2f} |"
    )
for title, key in [
    ("Mesh versus original Terrarium elevation", "dem_mesh_vs_source"),
    (
        "Previous backend sampling versus rendered triangles",
        "old_backend_nearest_vertex_vs_rendered",
    ),
]:
    v = report[key]
    lines += [
        "",
        f"{title}: {v['samples']} samples, RMSE {v['rmse_m']:.3f} m, maximum {v['max_abs_m']:.3f} m.",
    ]
lines += [
    "",
    "The backend now uses the same triangle interpolation as Godot. Source DEM precision has not improved. Zoom-14 tile pixels and 15 m mesh spacing are not measurements of survey accuracy.",
    "",
    "Visible building height sources: " + str(report["visible_building_heights"]),
    "",
    "Required next evidence: georeferenced local bare-earth DEM and independent control points with horizontal CRS, vertical datum, acquisition date and stated accuracy. Do not compare ellipsoidal GNSS heights directly with orthometric DEM heights.",
    "",
    "Official references: [Olympic Park map](https://www.ksponco.or.kr/olympicpark/map), [NGII data portal](https://map.ngii.go.kr/ms/map/NlipMap.do?menu=emap). The browser verified a 2025 Seongdong 37705 public DEM listing covering Olympic Park. Download clicks did not yield a retrievable file in this session; no NGII elevation file has been acquired. Resolution, CRS and vertical datum remain unverified until its metadata is obtained.",
]
(ROOT / "docs/geography-audit.md").write_text("\n".join(lines) + "\n")
assert max(r["projection_error_m"] for r in rows) < 1
print(
    json.dumps(
        {
            k: report[k]
            for k in [
                "dem_mesh_vs_source",
                "old_backend_nearest_vertex_vs_rendered",
                "visible_building_heights",
            ]
        },
        indent=2,
    )
)
