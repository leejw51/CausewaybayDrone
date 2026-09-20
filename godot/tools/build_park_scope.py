"""Preserve the mapped park perimeter and build an inward-buffered flight graph."""
from pathlib import Path
import json, math
from shapely.geometry import Point, LineString, Polygon
source=Path(__file__).with_name('build_real_map.py')
ns={'__file__':str(source)}
exec(compile(source.read_text().split('tiles={}')[0],str(source),'exec'),ns)
park=ns['park'];flight=park.buffer(-8);polys=ns['polys'];root=ns['ROOT']
def polygons(g):return [[[list(p) for p in poly.exterior.coords]]+[[list(p) for p in ring.coords] for ring in poly.interiors] for poly in polys(g)]
x0,z0,x1,z1=flight.bounds;nodes=[];lookup={};step=20
for x in range(math.ceil(x0/step)*step,int(x1),step):
 for z in range(math.ceil(z0/step)*step,int(z1),step):
  if flight.covers(Point(x,z)):
   lookup[(x,z)]=len(nodes);nodes.append([x,z])
edges=[[] for _ in nodes]
for i,(x,z) in enumerate(nodes):
 for dx,dz in [(20,0),(-20,0),(0,20),(0,-20),(20,20),(20,-20),(-20,20),(-20,-20)]:
  j=lookup.get((x+dx,z+dz))
  if j is not None and flight.covers(LineString([(x,z),nodes[j]])):edges[i].append(j)
data=json.loads((root/'data/real-map.json').read_text());region=park.buffer(250)
visible=[i for i,b in enumerate(data['buildings']) if Polygon(b['rings'][0]).intersects(region)]
out={'source':'OSM relation 6185423, preserved snapshot','metres_per_unit':1,'flight_inset_m':8,'building_context_m':250,'park_polygons':polygons(park),'flight_polygons':polygons(flight),'navigation':{'points':nodes,'edges':edges},'visible_building_indices':visible}
(root/'data/park-scope.json').write_text(json.dumps(out,separators=(',',':')))
print('PARK_SCOPE_READY',len(nodes),'navigation points;',len(visible),'nearby building components')
for p in [(130,-40),(130,-130),(300,-200),(500,-350)]:print(p,flight.covers(Point(*p)))
