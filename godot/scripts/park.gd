extends Node3D

var grass := material("8aab62")
var path_mat := material("d6c7a8")
var stone := material("e6ddd0")
var bark := material("6f6554")
var teal := material("227b82")
var rng := RandomNumberGenerator.new()
var tree_count := 0


func material(hex: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = 0.85
	return m


func mesh_node(mesh: Mesh, pos: Vector3, mat: Material, solid := false) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	add_child(n)
	n.position = pos
	if solid:
		n.create_trimesh_collision()
	return n


func box(pos: Vector3, size: Vector3, mat: Material, solid := false) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return mesh_node(m, pos, mat, solid)


func cylinder(
	pos: Vector3, radius: float, height: float, mat: Material, solid := false
) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 32
	return mesh_node(m, pos, mat, solid)


func sign_text(text: String, pos: Vector3, size := 60, color := Color("f4eddb")) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.018
	l.modulate = color
	l.outline_size = 3
	add_child(l)
	l.position = pos
	return l


func tree(pos: Vector3, height: float, autumn := false) -> void:
	tree_count += 1
	box(pos + Vector3.UP * height * .27, Vector3(.55, height * .54, .55), bark, true)
	var leaf := material(
		["44764b", "57884c", "69984f", "7da559"][rng.randi_range(0, 3)] if not autumn else "c9a44f"
	)
	var light_leaf := material("91b768" if not autumn else "deb966")
	# Chunky layered crowns suit the voxel visitors while keeping distinct silhouettes.
	if tree_count % 4 == 0:
		for tier in range(4):
			var width := height * (.68 - tier * .13)
			box(
				pos + Vector3(0, height * (.38 + tier * .15), 0),
				Vector3(width, height * .22, width),
				leaf,
				true
			)
	else:
		box(
			pos + Vector3(0, height * .67, 0),
			Vector3(height * .63, height * .35, height * .59),
			leaf,
			true
		)
		box(
			pos + Vector3(-height * .19, height * .57, height * .05),
			Vector3(height * .39, height * .28, height * .40),
			leaf,
			true
		)
		box(
			pos + Vector3(height * .19, height * .64, -height * .08),
			Vector3(height * .38, height * .30, height * .41),
			leaf,
			true
		)
		box(
			pos + Vector3(-height * .06, height * .87, 0),
			Vector3(height * .43, height * .20, height * .40),
			light_leaf,
			true
		)
		box(
			pos + Vector3(height * .10, height * .83, height * .20),
			Vector3(height * .24, height * .20, height * .22),
			light_leaf
		)


func _ready() -> void:
	rng.seed = 1988
	box(Vector3(0, -1, -30), Vector3(650, 2, 650), grass, true)
	box(Vector3(0, 0.025, 8), Vector3(66, .05, 105), path_mat)
	box(Vector3(0, .04, -43), Vector3(310, .07, 8), path_mat)
	box(Vector3(42, .04, -100), Vector3(7, .07, 180), path_mat)
	# Monument plaza paving, approach lanes and circular launch pad.
	for x in range(-30, 31, 6):
		box(Vector3(x, .06, 5), Vector3(.08, .02, 96), stone)
	for z in range(-42, 57, 6):
		box(Vector3(0, .06, z), Vector3(64, .02, .08), stone)
	cylinder(Vector3(0, .1, 43), 4, .12, teal)
	var pad := sign_text("H", Vector3(0, .18, 43), 180)
	pad.rotation.x = -PI / 2
	peace_gate()
	lake()
	# Rolling Mongchontoseong-inspired earthworks and solitary tree.
	for spec in [Vector3(-57, 5, -110), Vector3(-93, 3, -147), Vector3(-25, 3, -172)]:
		var hill := SphereMesh.new()
		hill.radius = 1
		hill.height = 2
		hill.radial_segments = 40
		var n := mesh_node(hill, Vector3(spec.x, -2, spec.z), grass)
		n.scale = Vector3(39, spec.y + 4, 29)
		n.create_trimesh_collision()
	tree(Vector3(-57, 7, -110), 13)
	sign_text("LONE TREE", Vector3(-57, 20, -110), 50)
	for i in range(150):
		var p := Vector3(rng.randf_range(-180, 180), 0, rng.randf_range(-195, 110))
		if preload("res://scripts/buildings.gd").is_building_area(p):
			continue
		if (
			absf(p.x) < 37
			or (p.x > 48 and p.x < 154 and p.z < -27 and p.z > -140)
			or (p.distance_to(Vector3(-57, 0, -110)) < 45)
			or absf(p.z + 43) < 9
		):
			continue
		tree(p, rng.randf_range(5, 10), i % 8 == 0)
	for side in [-1, 1]:
		for z in [22, 42, 62, 82]:
			tree(Vector3(side * 36, 0, z), 8.5, z == 62)
	# Flag avenue echoes the park's international plaza.
	var colors := ["e7e5d8", "ca6453", "5990a5", "dbb956", "799571"]
	for side in [-1, 1]:
		for i in range(10):
			var p := Vector3(side * 29, 0, 34 - i * 7)
			cylinder(p + Vector3.UP * 4.5, .065, 9, stone)
			box(p + Vector3(1.1, 8.1, 0), Vector3(2.2, 1.2, .055), material(colors[i % 5]))
	var buildings := Node3D.new()
	buildings.set_script(preload("res://scripts/buildings.gd"))
	add_child(buildings)
	# Destination and rescue stations.
	box(Vector3(-43, 2, 5), Vector3(10, 4, 7), stone, true)
	box(Vector3(-43, 4.2, 5), Vector3(12, .5, 9), teal, true)
	sign_text("PARK CAFE", Vector3(-43, 3, 8.56), 65, Color("23545a"))
	cylinder(Vector3(-43, .12, 17), 3, .15, teal)
	sign_text("01  /  COFFEE + DELI", Vector3(-43, 7, 17), 42)
	sign_text("02  /  RESCUE", Vector3(85, 8, -42), 48, Color("ffcf8a"))
	for i in range(10):
		var p := Vector3(-23, 0, 30 - i * 7)
		box(p + Vector3(0, .65, 0), Vector3(2, .18, .7), bark, true)
		box(p + Vector3(0, 1, .3), Vector3(2, .7, .13), bark)
	populate_walkers()


func populate_walkers() -> void:
	var routes: Array[PackedVector3Array] = []
	# Front plaza loops stay clear of the launch pad, benches and gate pillars.
	for side in [-1, 1]:
		for lane in range(3):
			var x := float(side) * (7.0 + lane * 4.0)
			routes.append(
				PackedVector3Array(
					[
						Vector3(x, 0, 48),
						Vector3(x, 0, -7),
						Vector3(x + side * 2.5, 0, -7),
						Vector3(x + side * 2.5, 0, 48)
					]
				)
			)
	# West promenade and bridge routes never cross the lawn or water surface.
	routes.append(
		PackedVector3Array(
			[Vector3(-110, 0, -44), Vector3(32, 0, -44), Vector3(32, 0, -41), Vector3(-110, 0, -41)]
		)
	)
	routes.append(
		PackedVector3Array(
			[
				Vector3(57, 1, -65.8),
				Vector3(142, 1, -65.8),
				Vector3(142, 1, -64.2),
				Vector3(57, 1, -64.2)
			]
		)
	)
	for i in range(32):
		var route: PackedVector3Array = routes[i % routes.size()].duplicate()
		if i % 3 == 1:
			route.reverse()
		var person := CharacterBody3D.new()
		person.name = "Visitor_%02d" % i
		person.set_script(preload("res://scripts/walker.gd"))
		person.route = route
		person.variant = i
		person.pace = .95 + (i % 5) * .13
		var fraction := .07 + floorf(float(i) / routes.size()) * .21 + (i % 3) * .037
		person.position = route[0].lerp(route[1], fraction) + Vector3.UP * .12
		person.waypoint = 1
		person.phase = i * .73
		add_child(person)


func peace_gate() -> void:
	for x in [-16, 16]:
		box(Vector3(x, 8, -20), Vector3(4.5, 16, 6), stone, true)
		box(Vector3(x, 8, -16.94), Vector3(3, 12, .12), material("b46644"))
		for y in range(3, 15, 2):
			box(Vector3(x, y, -16.83), Vector3(3.1, .25, .12), teal)
	# Raised wing profile, modeled as a closed extruded polygon.
	var profile := PackedVector2Array(
		[
			Vector2(-32, 23),
			Vector2(-23, 20),
			Vector2(-12, 18.5),
			Vector2(0, 18),
			Vector2(12, 18.5),
			Vector2(23, 20),
			Vector2(32, 23),
			Vector2(30, 18.5),
			Vector2(17, 16.3),
			Vector2(0, 15.5),
			Vector2(-17, 16.3),
			Vector2(-30, 18.5)
		]
	)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(profile)
	for z in [-25.0, -15.0]:
		for i in range(0, indices.size(), 3):
			var ids := [indices[i], indices[i + 1], indices[i + 2]]
			if z == -15:
				ids.reverse()
			for id in ids:
				st.add_vertex(Vector3(profile[id].x, profile[id].y, z))
	for i in profile.size():
		var a := profile[i]
		var b := profile[(i + 1) % profile.size()]
		for v in [
			Vector3(a.x, a.y, -25),
			Vector3(a.x, a.y, -15),
			Vector3(b.x, b.y, -15),
			Vector3(a.x, a.y, -25),
			Vector3(b.x, b.y, -15),
			Vector3(b.x, b.y, -25)
		]:
			st.add_vertex(v)
	st.generate_normals()
	var wing_mat := material("e6dfcd")
	wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_node(st.commit(), Vector3.ZERO, wing_mat, true)
	box(Vector3(0, 15.7, -20), Vector3(24, .2, 8), material("974c39"))
	sign_text("WORLD PEACE GATE", Vector3(0, 13.7, -14.8), 75, Color("37575a"))
	sign_text("SEOUL  1988", Vector3(0, 11.8, -14.7), 45, Color("37575a"))
	var ring_colors := ["3984aa", "343d43", "d85e50", "d9b64b", "559572"]
	for i in range(5):
		var ring := TorusMesh.new()
		ring.inner_radius = .78
		ring.outer_radius = 1.0
		var n := mesh_node(
			ring,
			Vector3(
				(i % 3) * 2.2 - 2.2 + (1.1 if i > 2 else 0.0), 10.1 - (1.1 if i > 2 else 0.0), -15
			),
			material(ring_colors[i])
		)
		n.rotation.x = PI / 2


func lake() -> void:
	var rim := cylinder(Vector3(100, .08, -84), 1, .15, path_mat)
	rim.scale = Vector3(52, 1, 49)
	var water := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode cull_disabled; void fragment(){ float w=sin(UV.x*150.0+TIME)*sin(UV.y*130.0-TIME*.7); ALBEDO=mix(vec3(.13,.43,.45),vec3(.24,.58,.58),w*.5+.5); ROUGHNESS=.28; METALLIC=.25; }"
	water.shader = shader
	var pond := cylinder(Vector3(100, .18, -84), 1, .1, water)
	pond.scale = Vector3(48, 1, 45)
	box(Vector3(100, .6, -65), Vector3(100, .6, 4), bark, true)
	for z in [-67.0, -63.0]:
		box(Vector3(100, 1.8, z), Vector3(100, .12, .12), stone)
		for x in range(52, 150, 5):
			cylinder(Vector3(x, 1.2, z), .06, 1.4, stone)
	sign_text("MONGCHON MOAT", Vector3(103, 4, -104), 65)
	var ring := TorusMesh.new()
	ring.inner_radius = .65
	ring.outer_radius = 1.05
	mesh_node(ring, Vector3(85, .5, -42), material("f58a42"))
