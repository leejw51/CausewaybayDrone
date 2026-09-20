"""Check landcover/road geometry against the authoritative terrain triangles."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
data = json.loads((ROOT / "godot/data/real-map.json").read_text())
t = data["terrain"]


def height(x, z):
    fx = min(max((x - t["x"]) / t["step"], 0), t["nx"] - 1.001)
    fz = min(max((z - t["z"]) / t["step"], 0), t["nz"] - 1.001)
    ix, iz = int(fx), int(fz)
    u, v = fx - ix, fz - iz
    i = iz * t["nx"] + ix
    a, b, c, d = (t["heights"][j] for j in [i, i + 1, i + t["nx"], i + t["nx"] + 1])
    return (
        a + (b - a) * u + (c - a) * v
        if u + v <= 1
        else d + (c - d) * (1 - u) + (b - d) * (1 - v)
    )


worst = 0
count = 0
for surface in data["surfaces"]:
    points = surface["triangles"]
    for i in range(0, len(points), 3):
        triangle = points[i : i + 3]
        p = [sum(v[a] for v in triangle) / 3 for a in range(3)]
        error = abs(p[1] - height(p[0], p[2]) - 0.09)
        worst = max(worst, error)
        assert error < 0.015, (surface["id"], error, p)
        count += 1
for road in data["roads"]:
    if not road["bridge"]:
        for x, y, z in road["points"]:
            assert abs(y - height(x, z) - 0.17) < 0.015, road["id"]
assert count > 0
print(
    f"TERRAIN_ALIGNMENT_OK: {count} landcover triangles; max surface error {worst:.4f} m; roads aligned"
)
