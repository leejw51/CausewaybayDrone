"""Build an offline, metre-scale scene from preserved OSM and Terrarium snapshots.
Requires Pillow and Shapely >=2.1. No network requests are made by this script.
"""
import sys, json, math, re, random
from pathlib import Path
from functools import lru_cache
from PIL import Image
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union, polygonize
from shapely import constrained_delaunay_triangles, make_valid

ROOT=Path(__file__).resolve().parents[1]
LAT,LON=37.5183131,127.1153937
phi=math.radians(LAT); a=6378137.; e2=0.00669437999014
N=a/math.sqrt(1-e2*math.sin(phi)**2)
M=a*(1-e2)/(1-e2*math.sin(phi)**2)**1.5
SX=math.pi/180*N*math.cos(phi); SZ=math.pi/180*M
def project(lat,lon): return ((lon-LON)*SX, -(lat-LAT)*SZ)
def unproject(x,z): return (LAT-z/SZ,LON+x/SX)
def rnd(x): return round(float(x),3)
def polys(g):
    if g.is_empty:return []
    if g.geom_type=='Polygon':return [g]
    return [p for c in getattr(g,'geoms',[]) for p in polys(c)]

elements={}
for source in ['osm-source.json','osm-park.json','osm-tower.json']:
    for e in json.loads((ROOT/'data'/source).read_text())['elements']:
        elements[(e['type'],e['id'])]=e
def line(g):return [project(p['lat'],p['lon']) for p in g if 'lat' in p]
def geometry(e):
    if e['type']=='way':
        p=line(e.get('geometry',[]))
        return make_valid(Polygon(p)) if len(p)>3 and p[0]==p[-1] else Polygon()
    if e['type']=='relation':
        rings={}
        for m in e.get('members',[]):
            p=line(m.get('geometry',[]))
            if len(p)>2:rings.setdefault(m.get('role','outer') or 'outer',[]).append(LineString(p))
        outer=unary_union(list(polygonize(rings.get('outer',[]))))
        inner=unary_union(list(polygonize(rings.get('inner',[]))))
        return make_valid(outer.difference(inner))
    return Polygon()

west,north=project(37.528,127.098); east,south=project(37.510,127.134)
extent=box(west,north,east,south)
park=geometry(elements[('relation',6185423)]).intersection(extent)
tiles={}
for f in (ROOT/'data/elevation').glob('14-*.png'):
    _,x,y=f.stem.split('-');tiles[(int(x),int(y))]=Image.open(f).convert('RGB')
def elevation(lat,lon):
    u=(lon+180)/360*16384*256
    v=(1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2*16384*256
    def pixel(x,y):
        im=tiles.get((x//256,y//256))
        if im is None:raise ValueError(f"Missing elevation tile 14-{x//256}-{y//256}; refusing invented 20 m fallback")
        r,g,b=im.getpixel((x%256,y%256));return r*256+g+b/256-32768
    ix,iy=math.floor(u),math.floor(v);fx,fy=u-ix,v-iy
    return (pixel(ix,iy)*(1-fx)+pixel(ix+1,iy)*fx)*(1-fy)+(pixel(ix,iy+1)*(1-fx)+pixel(ix+1,iy+1)*fx)*fy
datum=elevation(LAT,LON)
def raw_height(x,z):return elevation(*unproject(x,z))-datum
water=[];member_ways=set()
for e in elements.values():
    if e.get('tags',{}).get('natural')=='water' and e['type']=='relation':
        member_ways.update(m['ref'] for m in e.get('members',[]) if m['type']=='way')
for e in elements.values():
    if e.get('tags',{}).get('natural')!='water' or (e['type']=='way' and e['id'] in member_ways):continue
    for p in polys(geometry(e).intersection(extent)):
        if p.area<5:continue
        samples=sorted(raw_height(x,z) for x,z in p.exterior.coords)
        level=samples[len(samples)//4]
        water.append((p,level,e['id']))
def ground(x,z):
    p=Point(x,z)
    for lake,h,_ in water:
        if lake.contains(p):return h-.8
    return raw_height(x,z)
# Match Godot's terrain triangles exactly, including waterbed leveling.
step=15.;nx=math.ceil((east-west)/step)+1;nz=math.ceil((south-north)/step)+1
@lru_cache(maxsize=None)
def vertex_height(ix,iz): return rnd(ground(west+ix*step,north+iz*step))
def scene_height(x,z):
    fx=min(max((x-west)/step,0),nx-1.001);fz=min(max((z-north)/step,0),nz-1.001)
    ix,iz=int(fx),int(fz);u,v=fx-ix,fz-iz
    a,b,c,d=vertex_height(ix,iz),vertex_height(ix+1,iz),vertex_height(ix,iz+1),vertex_height(ix+1,iz+1)
    return a+(b-a)*u+(c-a)*v if u+v<=1 else d+(c-d)*(1-u)+(b-d)*(1-v)
def draped_triangles(p):
    # Clip mapped landcover to each terrain triangle: large lawn polygons must
    # never bridge over hills or leave visible terrain separated from collision.
    x0,z0,x1,z1=p.bounds
    result=[]
    for iz in range(max(0,int((z0-north)//step)),min(nz-1,int((z1-north)//step)+1)):
        for ix in range(max(0,int((x0-west)//step)),min(nx-1,int((x1-west)//step)+1)):
            x,z=west+ix*step,north+iz*step
            for corners in [[(x,z),(x,z+step),(x+step,z)],[(x+step,z),(x,z+step),(x+step,z+step)]]:
                clipped=p.intersection(Polygon(corners))
                for part in polys(clipped):
                    if part.area>1e-6:result+=surface_triangles(part,lambda x,z:scene_height(x,z)+.09)
    return result

def surface_triangles(p,height):
    result=[]
    for tri in constrained_delaunay_triangles(p).geoms:
        # Shapely XY maps to Godot XZ, reversing the surface handedness.
        for x,z in list(tri.exterior.coords)[:3][::-1]:
            result.append([rnd(x),rnd(height(x,z) if callable(height) else height),rnd(z)])
    return result

features=[]; buildings=[]; landmarks=[]; roads=[]; tree_points=[]
named={75956855:('KSPO DOME','dome',32),75956856:('OLYMPIC SWIMMING POOL','pool',25),75956853:('HANDBALL ARENA','arena',23),75956852:('WOORI ART HALL','hall',20),75956846:('OLYMPIC HALL','hall',20),415026027:('HANSEONG BAEKJE MUSEUM','museum',15),682920471:('SEOUL OLYMPIC PARKTEL','hotel',68),6185424:('SOMA MUSEUM','museum',10),16563734:('WORLD PEACE GATE','gate',24)}
relation_members=set()
tower_members={m['ref'] for m in elements[('relation',8824257)]['members'] if m['type']=='way'}
tower_point=elements[('node',12520558001)]
tower_base=raw_height(*project(tower_point['lat'],tower_point['lon']))
for e in elements.values():
    if e['type']=='relation' and e.get('tags',{}).get('building') and e['id']!=8824257:
        relation_members.update(m['ref'] for m in e.get('members',[]) if m['type']=='way')
def number(v,default):
    m=re.search(r'[-+]?[0-9]*\.?[0-9]+',str(v));return float(m.group()) if m else default
for e in elements.values():
    t=e.get('tags',{}); ident=e['id']
    if not ('building' in t or 'building:part' in t):continue
    if ident==8824257 or (e['type']=='way' and ident in relation_members):continue
    geom=geometry(e).intersection(extent)
    parts=polys(geom)
    if not parts:continue
    kind=named.get(ident,('', 'city',12))[1]
    default=named.get(ident,('', '',12))[2]
    h=number(t.get('height'),number(t.get('building:levels'),default/3)*3)
    bottom=number(t.get('min_height'),0)
    provenance='OSM height' if 'height' in t else ('OSM levels × 3 m (estimated)' if 'building:levels' in t else 'estimated height')
    center=geom.centroid
    base=raw_height(center.x,center.y)
    if ident in tower_members:base=tower_base
    for p in parts:
        if p.area<2:continue
        rings=[list(p.exterior.coords)[:-1]]+[list(r.coords)[:-1] for r in p.interiors]
        top=lambda x,z:base+h
        part_bottom=bottom
        if t.get('roof:shape')=='skillion' and 'roof:height' in t:
            heading=math.radians(number(t.get('roof:direction'),0))
            dx,dz=math.sin(heading),-math.cos(heading)
            projections=[x*dx+z*dz for x,z in p.exterior.coords]
            lo,hi=min(projections),max(projections)
            rh=number(t['roof:height'],0)
            top=lambda x,z:base+h-rh*(x*dx+z*dz-lo)/max(hi-lo,.001)
            if t.get('building:part')=='roof':part_bottom=max(bottom,h-rh)
        buildings.append(dict(id=ident,name=t.get('name:en',t.get('name','')),kind=kind,height=rnd(h),bottom=rnd(part_bottom),base=rnd(base),height_source=provenance,roof_shape=t.get('roof:shape','unspecified'),rings=[[[rnd(x),rnd(z)] for x,z in ring] for ring in rings],top_rings=[[rnd(top(x,z)) for x,z in ring] for ring in rings],roof=surface_triangles(p,top)))
    if ident in named:
        minx,minz,maxx,maxz=geom.bounds
        rect=geom.minimum_rotated_rectangle
        corners=list(rect.exterior.coords)
        edges=[(math.dist(corners[i],corners[i+1]),corners[i],corners[i+1]) for i in range(4)]
        length,pa,pb=max(edges)
        angle=-math.atan2(pb[1]-pa[1],pb[0]-pa[0])
        landmarks.append(dict(id=ident,name=named[ident][0],kind=kind,position=[rnd(center.x),rnd(base),rnd(center.y)],height=rnd(h),height_source=provenance,lat=unproject(center.x,center.y)[0],lon=unproject(center.x,center.y)[1],size=[rnd(maxx-minx),rnd(maxz-minz)],angle=angle))
# The tower's parts carry actual mapped height/min_height, including the 555 m crown.
tower=elements[('node',12520558001)]
tx,tz=project(tower['lat'],tower['lon'])
landmarks.append(dict(id=8824257,name='LOTTE WORLD TOWER',kind='tower',position=[rnd(tx),rnd(raw_height(tx,tz)),rnd(tz)],height=555,height_source='OSM height; LOTTE published height',lat=tower['lat'],lon=tower['lon'],size=[85,85],angle=0))

road_widths={'primary':15,'secondary':12,'tertiary':10,'residential':6,'service':4,'footway':2.5,'pedestrian':6,'path':2,'cycleway':2.5,'steps':2,'trunk':18,'living_street':5}
for e in elements.values():
    t=e.get('tags',{}); pts=line(e.get('geometry',[]))
    if 'highway' in t and len(pts)>1 and t.get('tunnel')!='yes' and t['highway'] not in ['platform','bus_stop']:
        path=LineString(pts).intersection(extent)
        width=number(t.get('width'),road_widths.get(t['highway'].replace('_link',''),5))
        if t.get('area')=='yes':continue
        for ln in ([path] if path.geom_type=='LineString' else getattr(path,'geoms',[])):
            if ln.geom_type!='LineString' or ln.length<.5:continue
            samples=[ln.interpolate(min(i*5,ln.length)) for i in range(math.ceil(ln.length/5)+1)]
            points=[[rnd(p.x),rnd(scene_height(p.x,p.y)+.17),rnd(p.y)] for p in samples]
            if t.get('bridge')=='yes':
                level=max(p[1] for p in points)+.7
                for p in points:p[1]=level
            roads.append(dict(id=e['id'],kind=t['highway'],width=width,points=points,inside_park=park.covers(ln),bridge=t.get('bridge')=='yes'))
    if len(pts)>3 and ('landuse' in t or 'leisure' in t or t.get('place')=='square' or t.get('area')=='yes') and 'building' not in t:
        p=geometry(e).intersection(extent)
        category='grass'
        if t.get('place')=='square' or t.get('area')=='yes':category='plaza'
        elif t.get('leisure')=='pitch':category='pitch'
        elif t.get('landuse') not in ['grass','forest','meadow','recreation_ground'] and t.get('leisure') not in ['park','garden']:continue
        if p.area>1:features.append(dict(id=e['id'],kind=category,triangles=draped_triangles(p)))
    if e['type']=='node' and t.get('natural')=='tree':
        x,z=project(e['lat'],e['lon']);tree_points.append([rnd(x),rnd(scene_height(x,z)),rnd(z),number(t.get('height'),9),True])
        if e['id']==3739451104:landmarks.append(dict(id=e['id'],name='LONE TREE',kind='tree',position=[rnd(x),rnd(scene_height(x,z)),rnd(z)],height=10,height_source='approximate tree height',lat=e['lat'],lon=e['lon'],size=[8,8],angle=0))
# Additional visual trees only within mapped woodland, never scattered across arbitrary lawns.
woods=[]
for e in elements.values():
    t=e.get('tags',{})
    if t.get('natural')=='wood' or t.get('landuse')=='forest':woods+=polys(geometry(e).intersection(park))
random.seed(1988)
for p in woods:
    x0,z0,x1,z1=p.bounds
    for _ in range(min(500,int(p.area/120))):
        x,z=random.uniform(x0,x1),random.uniform(z0,z1)
        if p.contains(Point(x,z)):tree_points.append([rnd(x),rnd(scene_height(x,z)),rnd(z),round(random.uniform(6,11),1),False])

# A regular 15 m terrain grid, sampled from the coarse global DEM; water is leveled.
step=15.;nx=math.ceil((east-west)/step)+1;nz=math.ceil((south-north)/step)+1
heights=[];colors=[]
for iz in range(nz):
    for ix in range(nx):
        x,z=west+ix*step,north+iz*step
        heights.append(vertex_height(ix,iz))
        colors.append(1 if park.covers(Point(x,z)) else 0)
data=dict(origin=dict(lat=LAT,lon=LON,metres_per_lon_degree=SX,metres_per_lat_degree=SZ,elevation_datum=datum),bounds=[west,north,east,south],terrain=dict(source="Mapzen Terrarium global DEM",source_accuracy="Coarse global DEM; 15m mesh is resampling, not a survey",x=west,z=north,step=step,nx=nx,nz=nz,heights=heights,colors=colors),buildings=buildings,landmarks=landmarks,roads=roads,surfaces=features,water=[dict(id=i,level=rnd(h),triangles=surface_triangles(p,h),rings=[[[rnd(x),rnd(z)] for x,z in p.exterior.coords]]) for p,h,i in water],trees=tree_points)
(ROOT/'data/real-map.json').write_text(json.dumps(data,separators=(',',':')))
stats={'buildings':len(buildings),'roads':len(roads),'water_polygons':len(water),'trees':len(tree_points),'landmarks':len(landmarks),'height_sources':{s:sum(b['height_source']==s for b in buildings) for s in set(b['height_source'] for b in buildings)},'metres_per_unit':1,'datum_m':datum}
(ROOT/'data/map-stats.json').write_text(json.dumps(stats,indent=2))
print(json.dumps(stats,indent=2))
for l in landmarks:print(l['name'],l['position'],l['height_source'])
