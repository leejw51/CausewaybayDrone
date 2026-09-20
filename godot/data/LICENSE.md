# Map and elevation data

The repository's code license does not replace the following data licenses.

OpenStreetMap source snapshots and their derived database (`real-map.json`) contain © OpenStreetMap contributors data, available under the Open Database License (ODbL) 1.0.

- https://www.openstreetmap.org/copyright
- https://opendatacommons.org/licenses/odbl/1-0/

Terrain source: Mapzen Terrain Tiles on AWS, accessed 2026-09-12. Global SRTM/GMTED terrain data courtesy of the U.S. Geological Survey; global ETOPO1 courtesy of NOAA. This project resamples elevation onto a 15 m mesh, subtracts a local datum, and levels mapped water bodies. Resampling does not increase the source DEM's accuracy.

- https://registry.opendata.aws/terrain-tiles/
- https://github.com/tilezen/joerd/blob/master/docs/attribution.md

The snapshots, query, converter and attribution are distributed here so the map-derived database remains available and reproducible.

Contact and postal-address tags were removed from the distributed snapshots before publication: `email`, `phone`, `fax`, `mobile`, `website`, `url`, `contact:*`, `addr:*` and social-media keys. `build_real_map.py` reads none of them, and `real-map.json` rebuilds byte-identically from the redacted snapshots. Re-run `map-query.overpass` against Overpass for the unredacted upstream data.
