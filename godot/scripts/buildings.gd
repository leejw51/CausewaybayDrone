extends Node3D

# Approximate placement read from the official Olympic Park visitor map.
# +X east, -Z north. Horizontal distances and heights are compressed for play.
const LANDMARKS := [
	{"name": "KSPO DOME", "position": Vector3(204, 0, -173), "radius": 37.0, "kind": "dome"},
	{
		"name": "OLYMPIC SWIMMING POOL",
		"position": Vector3(146, 0, -233),
		"radius": 36.0,
		"kind": "pool"
	},
	{"name": "HANDBALL ARENA", "position": Vector3(204, 0, -98), "radius": 32.0, "kind": "arena"},
	{"name": "WOORI ART HALL", "position": Vector3(204, 0, -34), "radius": 25.0, "kind": "hall"},
	{"name": "OLYMPIC HALL", "position": Vector3(154, 0, 22), "radius": 29.0, "kind": "hall"},
	{"name": "SOMA MUSEUM", "position": Vector3(69, 0, 71), "radius": 27.0, "kind": "museum"},
	{
		"name": "HANSEONG BAEKJE MUSEUM",
		"position": Vector3(144, 0, 100),
		"radius": 32.0,
		"kind": "museum"
	},
	{
		"name": "SEOUL OLYMPIC PARKTEL",
		"position": Vector3(-137, 0, -91),
		"radius": 24.0,
		"kind": "hotel"
	},
	{
		"name": "LOTTE WORLD TOWER",
		"position": Vector3(-262, 0, 213),
		"radius": 26.0,
		"kind": "tower"
	}
]

var concrete := material("c9c6bb")
var roof := material("e4e7df")
var glass := material("527d8c", .45)
var dark := material("405963")
var lawn := material("76985a")
var active_root: Node3D


static func is_building_area(p: Vector3) -> bool:
	for item in LANDMARKS:
		var center: Vector3 = item.position
		if Vector2(p.x - center.x, p.z - center.z).length() < item.radius + 6:
			return true
	return false


func material(hex: String, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.metallic = metal
	m.roughness = .45 if metal > 0 else .85
	return m


func shape(mesh: Mesh, p: Vector3, mat: Material, solid := true) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	active_root.add_child(n)
	n.position = p
	if solid:
		n.create_trimesh_collision()
	return n


func box(p: Vector3, dimensions: Vector3, mat: Material, solid := true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	return shape(mesh, p, mat, solid)


func cylinder(p: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 64
	return shape(mesh, p, mat)


func beam(a: Vector3, b: Vector3, width: float, mat: Material) -> void:
	var n := box((a + b) / 2, Vector3(width, width, a.distance_to(b)), mat, false)
	n.look_at(active_root.to_global(b), Vector3.UP)


func label(txt: String, p: Vector3) -> void:
	var l := Label3D.new()
	l.text = txt
	l.font_size = 46
	l.pixel_size = .025
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = Color("e4f3e9")
	l.outline_modulate = Color("183a40")
	l.outline_size = 8
	active_root.add_child(l)
	l.position = p
	l.visibility_range_end = 300
	l.visible = false  # HUD projects readable, constant-size labels above each landmark.


func _ready() -> void:
	name = "MapLandmarks"
	for item in LANDMARKS:
		active_root = Node3D.new()
		active_root.name = item.name
		add_child(active_root)
		active_root.position = item.position
		active_root.add_to_group("map_buildings")
		box(Vector3(0, .09, 0), Vector3(item.radius * 2, .18, item.radius * 2), material("b6b6aa"))
		match item.kind:
			"dome":
				stadium(29, 14, true)
			"arena":
				stadium(25, 11, false)
			"pool":
				swimming_pool()
			"hall":
				hall(item.name == "OLYMPIC HALL")
			"museum":
				museum(item.name == "HANSEONG BAEKJE MUSEUM")
			"hotel":
				hotel()
			"tower":
				tower()
		var label_height := 30.0
		if item.kind == "tower":
			label_height = 133
		if item.kind == "hotel":
			label_height = 44
		label(item.name, Vector3(0, label_height, 0))


func stadium(radius: float, height: float, cable_roof: bool) -> void:
	cylinder(Vector3(0, height / 2, 0), radius, height, concrete)
	cylinder(Vector3(0, height * .55, 0), radius + .12, height * .26, glass)
	cylinder(Vector3(0, height, 0), radius + 1.4, 1.2, roof)
	var dome := SphereMesh.new()
	dome.radius = 1
	dome.height = 2
	dome.radial_segments = 64
	dome.rings = 24
	var n := shape(dome, Vector3(0, height, 0), roof, false)
	n.scale = Vector3(radius, 5.5 if cable_roof else 8.0, radius)
	n.create_trimesh_collision()
	for i in range(24):
		var a := float(i) * TAU / 24
		var edge := Vector3(cos(a) * radius, height + 1, sin(a) * radius)
		box(Vector3(edge.x, height / 2, edge.z), Vector3(.6, height, .6), roof)
		if cable_roof:
			beam(edge, Vector3(cos(a) * 5, height + 5.3, sin(a) * 5), .16, dark)
	box(Vector3(0, 2.5, radius + 1.7), Vector3(17, 5, 4), glass)
	box(Vector3(0, 5.3, radius + 3), Vector3(21, .6, 6), roof)


func swimming_pool() -> void:
	box(Vector3(0, 7, 0), Vector3(49, 14, 43), concrete)
	box(Vector3(0, 8, 21.6), Vector3(44, 7, .3), glass)
	for x in [-18.0, -6.0, 6.0, 18.0]:
		var n := box(Vector3(x, 16, 0), Vector3(11, 2, 49), roof)
		n.rotation.z = .10 if x < 0 else -.10
		box(Vector3(x, 15.8, 0), Vector3(1.5, .5, 44), glass)
	for x in range(-22, 24, 5):
		box(Vector3(x, 8, 21.9), Vector3(.35, 10, .4), roof)


func hall(olympic: bool) -> void:
	var width := 39.0 if olympic else 34.0
	box(Vector3(0, 6, 0), Vector3(width, 12, 29), concrete)
	box(Vector3(0, 5, 14.7), Vector3(width - 4, 8, .4), glass)
	box(Vector3(0, 13, 0), Vector3(width + 3, 2, 32), roof)
	box(Vector3(0, 15, -4), Vector3(width - 8, 2, 19), dark)
	for x in range(-14, 15, 4):
		box(Vector3(x, 6, 15), Vector3(.5, 11, .5), roof)
	box(Vector3(0, 4, 19), Vector3(16, .5, 9), roof)


func museum(baekje: bool) -> void:
	var sandstone := material("b9a18a")
	box(Vector3(0, 3, 0), Vector3(43, 6, 29), sandstone)
	box(Vector3(-10, 5, -5), Vector3(22, 10, 22), sandstone)
	box(Vector3(0, 2.8, 14.8), Vector3(38, 4, .4), glass)
	if baekje:
		var n := box(Vector3(7, 7, 0), Vector3(31, 1, 32), lawn)
		n.rotation.z = -.17
	else:
		box(Vector3(11, 7, -4), Vector3(19, 8, 20), roof)
		cylinder(Vector3(13, 1.5, 21), 1.6, 3, material("ae6241"))


func hotel() -> void:
	box(Vector3(0, 18, 0), Vector3(27, 36, 13), concrete)
	box(Vector3(0, 3, 5), Vector3(37, 6, 23), concrete)
	for y in range(7, 35, 3):
		for z in [-6.6, 6.6]:
			box(Vector3(0, y, z), Vector3(25, 1.6, .2), glass, false)
	for x in range(-12, 13, 4):
		box(Vector3(x, 20, 6.8), Vector3(.5, 30, .4), roof, false)
	box(Vector3(0, 38, 0), Vector3(19, 4, 9), roof)


func tower() -> void:
	# Tapered glass shaft with floor bands and split crown, rather than the old cone.
	var glass_tower := material("8eb7c7", .55)
	var levels := 24
	for i in range(levels):
		var t := float(i) / levels
		var mesh := CylinderMesh.new()
		mesh.bottom_radius = 11.5 * (1.0 - pow(t, 1.7) * .83)
		mesh.top_radius = 11.5 * (1.0 - pow(float(i + 1) / levels, 1.7) * .83)
		mesh.height = 4.7
		mesh.radial_segments = 12
		shape(mesh, Vector3(0, 2.35 + i * 4.7, 0), glass_tower)
		cylinder(Vector3(0, i * 4.7, 0), mesh.bottom_radius + .08, .17, roof)
	for side in [-1, 1]:
		var n := box(Vector3(side * 1.6, 117, 0), Vector3(1.3, 14, 3.1), glass_tower)
		n.rotation.z = side * .06
	box(Vector3(0, 3, 0), Vector3(42, 6, 35), glass)
