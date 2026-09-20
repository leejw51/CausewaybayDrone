extends Node3D

var scope: Dictionary
var flight_polygons: Array = []
var data: Dictionary
var landmarks: Array
var tree_count := 0
var wildlife: Node3D
var path_routes: Array[PackedVector3Array] = []
var delivery_point := Vector3.ZERO
var rescue_point := Vector3.ZERO
var terrain: Dictionary
var source_bounds: Rect2
var water_nodes: Array[MeshInstance3D] = []


func vec(p: Array) -> Vector3:
	return Vector3(p[0], p[1], p[2])


func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/real-map.json"))
	scope = JSON.parse_string(FileAccess.get_file_as_string("res://data/park-scope.json"))
	for polygon in scope.flight_polygons:
		var rings: Array[PackedVector2Array] = []
		for source_ring in polygon:
			var ring := PackedVector2Array()
			for p in source_ring:
				ring.append(Vector2(p[0], p[1]))
			rings.append(ring)
		flight_polygons.append(rings)
	landmarks = data.landmarks
	terrain = data.terrain
	var b: Array = data.bounds
	source_bounds = Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1])
	make_terrain()
	make_surfaces()
	make_roads()
	make_buildings()
	make_trees()
	if ResourceLoader.exists("res://assets/park-dressing.glb"):
		add_child(load("res://assets/park-dressing.glb").instantiate())
	wildlife = preload("res://scripts/park_wildlife.gd").new()
	wildlife.park = self
	add_child(wildlife)
	make_visitors()
	# Fictional mission waypoints sit on real mapped footpaths.
	delivery_point = Vector3(45, ground_height(45, 55) + 2, 55)
	rescue_point = Vector3(165, ground_height(165, -170) + 3, -170)
	print(
		(
			"REAL_MAP_READY: %d footprints, %d mapped road/path ways, %d landmarks"
			% [data.buildings.size(), data.roads.size(), landmarks.size()]
		)
	)


func in_flight_area(p: Vector3) -> bool:
	var point := Vector2(p.x, p.z)
	for polygon in flight_polygons:
		if not Geometry2D.is_point_in_polygon(point, polygon[0]):
			continue
		var hole := false
		for i in range(1, polygon.size()):
			hole = hole or Geometry2D.is_point_in_polygon(point, polygon[i])
		if not hole:
			return true
	return false


func flight_segment(a: Vector3, b: Vector3) -> bool:
	if not in_flight_area(a) or not in_flight_area(b):
		return false
	var p := Vector2(a.x, a.z)
	var q := Vector2(b.x, b.z)
	if p.distance_squared_to(q) < .000001:
		return true
	for polygon in flight_polygons:
		for ring in polygon:
			for i in ring.size():
				if (
					Geometry2D.segment_intersects_segment(
						p, q, ring[i], ring[(i + 1) % ring.size()]
					)
					!= null
				):
					return false
	return true


func ground_height(x: float, z: float) -> float:
	var fx := clampf((x - float(terrain.x)) / float(terrain.step), 0, float(terrain.nx) - 1.0)
	var fz := clampf((z - float(terrain.z)) / float(terrain.step), 0, float(terrain.nz) - 1.0)
	var ix := mini(int(fx), int(terrain.nx) - 2)
	var iz := mini(int(fz), int(terrain.nz) - 2)
	var n := int(terrain.nx)
	var heights: Array = terrain.heights
	var u := fx - ix
	var v := fz - iz
	var a := float(heights[iz * n + ix])
	var b := float(heights[iz * n + ix + 1])
	var c := float(heights[(iz + 1) * n + ix])
	var d := float(heights[(iz + 1) * n + ix + 1])
	return (
		a + (b - a) * u + (c - a) * v if u + v <= 1 else d + (c - d) * (1 - u) + (b - d) * (1 - v)
	)


func landmark(title: String) -> Dictionary:
	for item in landmarks:
		if item.name == title:
			return item
	return {}


func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = .85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func ground_material(texture_name: String, mixed := false) -> Material:
	var styled_name := (
		"meadow-v2-codex.png" if texture_name == "park-grass.png" else "limestone-v2-codex.png"
	)
	var path := "res://assets/textures/" + styled_name
	if not ResourceLoader.exists(path):
		var fallback := material(Color.WHITE)
		fallback.vertex_color_use_as_albedo = true
		return fallback
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/park_ground.gdshader")
	mat.set_shader_parameter("ground_texture", load(path))
	mat.set_shader_parameter("mixed_city", mixed)
	mat.set_shader_parameter("paving_texture", load("res://assets/textures/limestone-v2-codex.png"))
	mat.set_shader_parameter("tile_metres", 4.0)
	mat.set_shader_parameter("paving", texture_name != "park-grass.png")
	if texture_name == "park-grass.png":
		mat.set_shader_parameter("surface_tint", Color("ffffff"))
	if texture_name == "park-earth.png":
		mat.set_shader_parameter("surface_tint", Color("ffffff"))
	return mat


func builder(flat := true) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if flat:
		st.set_smooth_group(-1)
	return st


func triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color := Color.WHITE) -> void:
	st.set_color(color)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func finish(st: SurfaceTool, mat: Material, title: String, solid := false) -> MeshInstance3D:
	st.generate_normals()
	var mesh := st.commit()
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = mesh
	node.material_override = mat
	add_child(node)
	if solid:
		node.create_trimesh_collision()
		for child in node.get_children():
			for collider in child.get_children():
				if collider is CollisionShape3D and collider.shape is ConcavePolygonShape3D:
					collider.shape.backface_collision = true
	return node


func make_terrain() -> void:
	var st := builder(false)
	var nx := int(terrain.nx)
	var nz := int(terrain.nz)
	for z in range(nz - 1):
		for x in range(nx - 1):
			var ids := [z * nx + x, z * nx + x + 1, (z + 1) * nx + x, (z + 1) * nx + x + 1]
			for corner in [0, 2, 1, 1, 2, 3]:
				var id: int = ids[corner]
				st.set_color(
					Color(.47, .57, .35, 1) if terrain.colors[id] == 1 else Color(.7, .68, .63, 0)
				)
				st.add_vertex(
					Vector3(
						float(terrain.x) + (id % nx) * float(terrain.step),
						terrain.heights[id],
						float(terrain.z) + floorf(float(id) / nx) * float(terrain.step)
					)
				)
	var mat := material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	finish(st, ground_material("park-grass.png", true), "DEM terrain (15 m sampling)", true)


func make_surfaces() -> void:
	var surfaces := builder(false)
	for f in data.surfaces:
		var col := Color("849863")
		if f.kind == "plaza":
			col = Color(.77, .74, .65, 0)
		if f.kind == "pitch":
			col = Color("718b6a")
		for p in f.triangles:
			surfaces.set_color(col)
			surfaces.add_vertex(vec(p))
	var mat := material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	finish(surfaces, ground_material("park-grass.png", true), "Mapped landcover")
	var water_mat := ShaderMaterial.new()
	water_mat.shader = preload("res://assets/lake_water.gdshader")
	for f in data.water:
		var water := builder()
		for p in f.triangles:
			water.add_vertex(vec(p) + Vector3.UP * .1)
		var node := finish(water, water_mat, "Water_%s" % str(f.id))
		node.layers = 2
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		water_nodes.append(node)
		if int(f.id) in [6968154, 222074696, 9856886]:
			var probe := ReflectionProbe.new()
			probe.name = "LakeReflection_%s" % str(f.id)
			var bounds := node.get_aabb()
			probe.position = bounds.get_center() + Vector3.UP * 25
			probe.size = Vector3(
				maxf(bounds.size.x + 400, 600), 240, maxf(bounds.size.z + 400, 600)
			)
			probe.max_distance = 1600
			probe.cull_mask = 1  # Exclude water itself from the captured scene.
			probe.update_mode = ReflectionProbe.UPDATE_ONCE
			probe.enable_shadows = false
			probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
			probe.intensity = .7
			probe.add_to_group("water_reflection_probes")
			add_child(probe)


func make_roads() -> void:
	var st := builder()
	var bridges := builder()
	var trails := builder()
	var trail_count := 0
	var bridge_count := 0
	for road in data.roads:
		var pts: Array = road.points
		var walkable: bool = road.kind in ["footway", "path", "pedestrian"]
		var color := Color("c9c0a8") if walkable else Color("606668")
		if road.kind == "cycleway":
			color = Color("a0796c")
		var target := bridges if road.bridge else trails if walkable else st
		if walkable and not road.bridge:
			trail_count += 1
		if road.bridge:
			bridge_count += 1
		for i in range(pts.size() - 1):
			var a := vec(pts[i])
			var b := vec(pts[i + 1])
			var delta := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
			var side := Vector3(-delta.z, 0, delta.x) * float(road.width) / 2
			var corners: Array[Vector3] = [a - side, a + side, b - side, b + side]
			if not road.bridge:
				for k in corners.size():
					corners[k].y = ground_height(corners[k].x, corners[k].z) + .17
			triangle(target, corners[0], corners[1], corners[2], color)
			triangle(target, corners[1], corners[3], corners[2], color)
		if road.inside_park and walkable and pts.size() > 8:
			var route := PackedVector3Array()
			for i in range(0, pts.size(), 2):
				route.append(vec(pts[i]))
			if route[0].distance_to(Vector3.ZERO) < 550:
				path_routes.append(route)
	var mat := material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	finish(st, mat, "Mapped road and pedestrian network")
	if trail_count > 0:
		finish(trails, ground_material("park-earth.png"), "Textured mapped walking trails")
	if bridge_count > 0:
		finish(bridges, mat, "Mapped bridges", true)


func make_buildings() -> void:
	var st := builder()
	for building_index in scope.visible_building_indices:
		var b: Dictionary = data.buildings[building_index]
		if b.kind == "gate" and ResourceLoader.exists("res://assets/world-peace-gate.glb"):
			continue
		var top := float(b.base) + float(b.height)
		var bottom := float(b.base) + float(b.bottom) - 1.0
		if b.kind == "gate":
			bottom = top - 2.5
		var shade := .72 + float(int(b.id) % 13) * .012
		var color: Color = (
			[Color("e8c179"), Color("87bcc5"), Color("edb9a2"), Color("a3cba1"), Color("d5cfaa")][posmod(
				int(b.id), 5
			)]
			* shade
		)
		color.a = 1.0
		if b.height > 100:
			color = Color("7da1ad")
		for ring_index in b.rings.size():
			var ring: Array = b.rings[ring_index]
			for i in ring.size():
				var p: Array = ring[i]
				var q: Array = ring[(i + 1) % ring.size()]
				var a := Vector3(p[0], bottom, p[1])
				var c := Vector3(q[0], b.top_rings[ring_index][(i + 1) % ring.size()], q[1])
				var d := Vector3(p[0], b.top_rings[ring_index][i], p[1])
				# UV coordinates are physical metres along each facade, independent of bearing.
				var edge_length := Vector2(q[0] - p[0], q[1] - p[1]).length()
				var wall_color := color
				wall_color.a = 0.0 if b.kind == "gate" else 1.0
				var corners := [a, c, d, a, Vector3(q[0], bottom, q[1]), c]
				var u_values := [0.0, edge_length, 0.0, 0.0, edge_length, edge_length]
				for j in 6:
					st.set_color(wall_color)
					st.set_uv(Vector2(u_values[j], corners[j].y - float(b.base)))
					st.add_vertex(corners[j])
			for p in b.roof:
				st.set_color(Color(color.r, color.g, color.b, 0.0))
				st.set_uv(Vector2(p[0], p[2]))
				st.add_vertex(vec(p))
	var mat := material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	var facade := ShaderMaterial.new()
	facade.shader = preload("res://assets/architectural_facade.gdshader")
	if ResourceLoader.exists("res://assets/textures/toy-plastic-codex.png"):
		facade.set_shader_parameter(
			"concrete_texture", load("res://assets/textures/toy-plastic-codex.png")
		)
	finish(st, facade, "OSM building footprints and height extrusions", true)
	# Preserve the monument's open passage. The mapped roof footprint is above.
	var gate := landmark("WORLD PEACE GATE")
	var center := vec(gate.position)
	if ResourceLoader.exists("res://assets/world-peace-gate.glb"):
		var monument: Node3D = load("res://assets/world-peace-gate.glb").instantiate()
		monument.name = "WorldPeaceGate"
		add_child(monument)
		monument.position = center
		monument.rotation.y = gate.angle
		add_monument_collisions(monument)
		return
	var orientation := Basis(Vector3.UP, float(gate.angle))
	for side in [-1, 1]:
		var m := BoxMesh.new()
		m.size = Vector3(5, 20, 7)
		var n := MeshInstance3D.new()
		n.mesh = m
		n.material_override = material(Color("dfd4bf"))
		add_child(n)
		n.position = center + orientation * Vector3(side * 18, 10, 0)
		n.rotation.y = gate.angle
		n.create_trimesh_collision()


func add_monument_collisions(node: Node) -> void:
	if node is MeshInstance3D:
		node.create_trimesh_collision()
	for child in node.get_children():
		if child is Node3D and not child is StaticBody3D:
			add_monument_collisions(child)


func make_trees() -> void:
	# Approximate crowns at mapped tree points; species and crown widths are not surveyed.
	var bark := preload("res://scripts/toy_material.gd").create(Color("865331"))
	var foliage := preload("res://scripts/toy_material.gd").create(Color("57a52f"))
	for p in data.trees:
		if Vector2(p[0] - 440.508, p[2] + 491.397).length() < 8:
			continue
		tree_count += 1
		var trunk := CylinderMesh.new()
		trunk.bottom_radius = .35
		trunk.top_radius = .25
		trunk.height = p[3] * .6
		var n := MeshInstance3D.new()
		n.mesh = trunk
		n.material_override = bark
		add_child(n)
		n.position = Vector3(p[0], p[1] + p[3] * .3, p[2])
		n.create_trimesh_collision()
		var crown := SphereMesh.new()
		crown.radius = 1
		crown.height = 2
		crown.radial_segments = 16
		crown.rings = 8
		for cluster in 5:
			var angle := cluster * 2.39996 + tree_count
			var leaves := MeshInstance3D.new()
			leaves.mesh = crown
			leaves.material_override = foliage
			add_child(leaves)
			var spread: float = p[3] * (.12 if cluster > 0 else 0.0)
			leaves.position = Vector3(
				p[0] + cos(angle) * spread,
				p[1] + p[3] * (.70 + cluster * .025),
				p[2] + sin(angle) * spread
			)
			leaves.scale = Vector3(.23, .25, .21) * float(p[3])


func make_visitors() -> void:
	path_routes.sort_custom(
		func(a: PackedVector3Array, b: PackedVector3Array): return a[0].length() < b[0].length()
	)
	for i in range(mini(32, path_routes.size())):
		var path := path_routes[i]
		var route := path.duplicate()
		# Return on the same mapped path instead of cutting across water/lawns.
		for j in range(path.size() - 2, 0, -1):
			route.append(path[j])
		var person := CharacterBody3D.new()
		person.set_script(preload("res://scripts/walker.gd"))
		person.route = route
		person.position = route[0] + Vector3.UP * .25
		person.waypoint = 1
		person.variant = i
		person.pace = 1.1 + (i % 5) * .1
		add_child(person)
