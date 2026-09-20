# Olympic Park geographic audit

NOT VERIFIED: no independent surveyed ground control or local high-resolution DEM supplied

This audit checks numerical conversion and model consistency, not agreement with surveyed reality. Waterbed modification areas are excluded from the DEM comparison.

| Landmark | Projection distance error (m) | DEM altitude (m) |
|---|---:|---:|
| OLYMPIC HALL | 0.0237 | 26.86 |
| WOORI ART HALL | 0.0088 | 22.66 |
| HANDBALL ARENA | 0.0059 | 24.29 |
| KSPO DOME | 0.0060 | 31.28 |
| OLYMPIC SWIMMING POOL | 0.0168 | 30.31 |
| HANSEONG BAEKJE MUSEUM | 0.0077 | 31.19 |
| SEOUL OLYMPIC PARKTEL | 0.0004 | 23.39 |
| SOMA MUSEUM | 0.0018 | 26.33 |
| WORLD PEACE GATE | 0.0003 | 18.69 |
| LOTTE WORLD TOWER | 0.0376 | 25.80 |
| LONE TREE | 0.0091 | 32.06 |

Mesh versus original Terrarium elevation: 1416 samples, RMSE 0.262 m, maximum 4.246 m.

Previous backend sampling versus rendered triangles: 1416 samples, RMSE 0.918 m, maximum 5.574 m.

The backend now uses the same triangle interpolation as Godot. Source DEM precision has not improved. Zoom-14 tile pixels and 15 m mesh spacing are not measurements of survey accuracy.

Visible building height sources: {'estimated height': 132, 'OSM height': 212, 'OSM levels × 3 m (estimated)': 52}

Required next evidence: georeferenced local bare-earth DEM and independent control points with horizontal CRS, vertical datum, acquisition date and stated accuracy. Do not compare ellipsoidal GNSS heights directly with orthometric DEM heights.

Official references: [Olympic Park map](https://www.ksponco.or.kr/olympicpark/map), [NGII data portal](https://map.ngii.go.kr/ms/map/NlipMap.do?menu=emap). The browser verified a 2025 Seongdong 37705 public DEM listing covering Olympic Park. Download clicks did not yield a retrievable file in this session; no NGII elevation file has been acquired. Resolution, CRS and vertical datum remain unverified until its metadata is obtained.
