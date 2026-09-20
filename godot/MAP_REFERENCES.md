# Geographic accuracy and provenance

The active scene uses `scripts/real_map.gd` and `data/real-map.json`. The earlier compressed `park.gd` / `buildings.gd` layouts are no longer active.

## Coordinates and scale

Origin: **37.5183131° N, 127.1153937° E**, at the mapped World Peace Gate footprint. Positions are converted using local WGS84 ellipsoid radii. +X is east, -Z is north, and **one Godot unit is one metre**. No horizontal or vertical scene compression is applied. A geodesic-distance regression independently checks the projection (within 4 m over the gate-to-KSPO baseline).

The source extract covers 37.510–37.528° N, 127.098–127.134° E. Buildings, including surrounding city blocks, use source footprint vertices and rotations. Roads and paths use mapped centerlines. Water multipolygons retain shorelines and holes. Museums, Parktel, stadiums, Lotte World Tower and Lone Tree use source coordinates rather than positions guessed from a diagram.

## Sources preserved in this project

- OpenStreetMap via Overpass, downloaded 2026-09-12: `osm-source.json`, `osm-park.json`, `osm-tower.json`. The main query is `map-query.overpass`. Supplemental queries retrieve park boundary/woods/plazas and Lotte building parts. Source feature IDs remain in the generated database.
- [OpenStreetMap map](https://www.openstreetmap.org/#map=16/37.5190/127.1210), [license](https://www.openstreetmap.org/copyright).
- [Official Olympic Park map](https://www.ksponco.or.kr/olympicpark/map) provides a cross-check of landmark identity and relative layout.
- [Mapzen/USGS terrain tiles](https://registry.opendata.aws/terrain-tiles/), six zoom-14 Terrarium tiles preserved in `data/elevation/`. Decoding is R × 256 + G + B / 256 − 32768 metres. Elevation is bilinearly sampled and then meshed at 15 m spacing; finer mesh spacing does not imply survey accuracy. Water is leveled and terrain under water is lowered by 0.8 m to avoid surface overlap.
- [LOTTE directions](https://www.lotte.co.kr/cscenter/directions.do) and mapped 555 m tower height. Mapped tower parts retain explicit heights and roof slopes/directions; the mapped highest part is 554.5 m. All tower parts use the same base elevation.

## Verified in data versus still approximate

| Property | Status |
|---|---|
| Landmark coordinates, footprint orientation, distances | Derived directly from OSM, subject to source accuracy |
| Building and building-part footprints | 1,563 imported polygon components |
| Road/path centerlines | 1,655 imported ways/segments |
| Water | 9 clipped polygon components, original geometry preserved |
| Heights | 830 components have OSM height tags; 172 use mapped floor count × assumed 3 m; 561 use explicit fallback estimates |
| Tree positions | 19 mapped tree points; source is incomplete, so this is not the park's full tree inventory |
| Terrain | Coarse public elevation model; not surveyed ground/LiDAR, may include surface artifacts |
| Facades and unspecified roof forms | Simplified massing, not photogrammetry or construction drawings |
| Road widths | Width tags where present; otherwise class-based estimates |
| Stylized Blender characters, drone and delivery/rescue tasks | Fictional game elements; visitors follow mapped paths |
| Sky | Stylized cloud shader and tuned daylight; not live weather |

Each building component carries `height_source`. The game is geographically grounded, but it must not be described as a fully surveyed or photorealistic replica.

## Rebuild and validation

Run `python3 godot/tools/build_real_map.py` with Pillow and Shapely 2.1+ installed. It uses the preserved local snapshots and makes no network requests. Use `uv run --python 3.12 --with pillow --with "shapely>=2.1" python godot/tools/build_real_map.py` for an isolated rebuild environment.

`real_map_test.gd` checks independent geodesic distance, true bearings, uncompressed landmark heights, imported counts, physical roof collision, flight, mapped-path visitors and mission interactions. Godot loads the generated JSON offline; Python is only needed to rebuild the database.

## Lone Tree and vegetation likeness

The [official nine sights description](https://www.ksponco.or.kr/menu.es?mid=a20107010000) identifies the Lone Tree as an approximately 10 m arborvitae. The Blender mesh is normalized to that height and uses tapered branches with an irregular oval crown. Branch geometry and crown width are artistic estimates. The default viewing preset now approaches pedestrian eye height instead of looking down from above.

Other mapped trees use rounded, textured crowns instead of cubic foliage. Their species and canopy dimensions remain approximate. The supplemental `vegetation-query.overpass` / `osm-vegetation.json` snapshot returned three woodland polygons outside the park and did not resolve its missing interior tree inventory; it is retained as research provenance and is not used to invent extra mapped tree positions.

Grass, soil, bark and foliage are generated material textures, not photographic measurements. Better resemblance still requires local high-resolution terrain, a complete vegetation inventory and reference-based building facades.

An earlier daylight preset used [Godot PhysicalSkyMaterial](https://docs.godotengine.org/en/stable/classes/class_physicalskymaterial.html), which derives its sun from the directional light. Atmospheric settings and exposure are chosen for presentation, not calibrated from a Seoul weather station. The procedural facade grid is an estimated visual treatment over the unchanged source geometry.

Prototype scope: `park-scope.json` retains the original map coordinates and defines an 8 m inward flight boundary. Rendering selects 396 building components intersecting a 250 m park buffer. `park-dressing.json` adds 180 stylized tree groups beside mapped paths; these are authored scenery, not measured tree positions. DEM source accuracy is unchanged by the denser terrain mesh.


## Numerical audit (2026-09-13)

See `../docs/geography-audit.md` and its machine-readable JSON, reproduced by `tools/audit_geography.py` with Pillow and pyproj. Independent WGS84 geodesics put the largest landmark projection distance discrepancy below 0.04 m. This measures conversion correctness, **not** OSM positional accuracy.

Across 1,416 sampled non-water park points, the former backend nearest-vertex ground sampling differed from the rendered triangular terrain by up to 5.574 m (RMSE 0.918 m). Rust now uses matching triangle interpolation; regression tests cover both triangle halves and boundary clamping. Building clearance remains conservative axis-aligned bounds. Raw DEM versus triangulated mesh RMSE is 0.262 m, with a 4.246 m maximum. Fine terrain detail absent from the source cannot be recovered through interpolation.

The NGII browser lists a 2025 Seongdong 37705 public DEM covering the park; downloading did not return a retrievable file during this run. No NGII elevation has been imported, and its resolution and vertical datum have not been established. Independent surveyed control points remain necessary before reporting real-world elevation accuracy.

## Authored prototype direction (2026-09-13)

The user chose to proceed without NGII downloads. No NGII data is used. Existing OSM and Terrarium snapshots remain the geographic foundation; finer visual details are authored approximations. `blender/world_peace_gate.blend` replaces the plain gate extrusion with a curved ivory wing roof, stone piers, recessed reliefs and original coloured soffit panels. The nominal 62 × 37 × 24 m envelope is retained, but the sculpture, ornament and structural details are an artistic likeness, not survey reconstruction. Its placement uses the existing mapped centre and bearing. Godot collisions follow the exported mesh and keep the central passage open.
