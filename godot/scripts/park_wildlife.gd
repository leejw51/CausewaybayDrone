extends Node3D

var park: Node3D
var sim: Node3D
var lone_tree: Node3D
var animals: Array[Dictionary] = []
var targets: Array[Dictionary] = []
var blocked: Array[PackedVector2Array] = []
var clock := 0.0
var rng := RandomNumberGenerator.new()


func part(parent: Node3D, at: Vector3, dimensions: Vector3, color: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	node.material_override = preload("res://scripts/toy_material.gd").create(Color(color))
	parent.add_child(node)
	node.position = at
	return node


func _ready() -> void:
	rng.seed = 3739451104
	var mapped: Dictionary = park.landmark("LONE TREE")
	lone_tree = Node3D.new()
	lone_tree.name = "LoneTree"
	add_child(lone_tree)
	lone_tree.position = park.vec(mapped.position)
	lone_tree.position.y = park.ground_height(lone_tree.position.x, lone_tree.position.z)
	if ResourceLoader.exists("res://assets/lone-tree.glb"):
		var model: Node3D = load("res://assets/lone-tree.glb").instantiate()
		lone_tree.add_child(model)
		configure_foliage(model)
		add_tree_colliders(model)
	else:
		var trunk := part(lone_tree, Vector3(0, 2.4, 0), Vector3(.65, 4.8, .65), "685442")
		trunk.create_trimesh_collision()
		# Layered, irregular evergreen crown with a recognisable solitary silhouette.
		for tier in 5:
			var width := 6.8 - tier * 1.05
			for side in 3:
				var angle := side * TAU / 3 + tier * .8
				var leaf := part(
					lone_tree,
					Vector3(cos(angle) * width * .17, 4.3 + tier * 1.05, sin(angle) * width * .17),
					Vector3(width * .72, 1.8, width * .72),
					["42633d", "527647", "658550"][side]
				)
				leaf.rotation.y = angle
				leaf.create_trimesh_collision()
	targets.append({"node": lone_tree})
	var habitat := Rect2(
		Vector2(lone_tree.position.x - 37, lone_tree.position.z - 37), Vector2(74, 74)
	)
	for feature in park.data.water + park.data.buildings:
		var polygon := PackedVector2Array()
		for p in feature.rings[0]:
			polygon.append(Vector2(p[0], p[1]))
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for p in polygon:
			bounds = bounds.expand(p)
		if bounds.intersects(habitat):
			blocked.append(polygon)
	var meadow := preload("res://scripts/meadow_detail.gd").new()
	meadow.name = "MeadowDetail"
	add_child(meadow)
	meadow.populate(park, lone_tree.position)
	for i in 9:
		make_animal(i, i >= 3)


func configure_foliage(node: Node) -> void:
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			var mat = node.mesh.surface_get_material(surface)
			if mat is StandardMaterial3D and "Codex" in mat.resource_name:
				var foliage: StandardMaterial3D = mat.duplicate()
				foliage.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				foliage.alpha_scissor_threshold = .4
				foliage.cull_mode = BaseMaterial3D.CULL_DISABLED
				foliage.texture_filter = (
					BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				)
				node.set_surface_override_material(surface, foliage)
	for child in node.get_children():
		configure_foliage(child)


func add_tree_colliders(node: Node) -> void:
	if node is MeshInstance3D:
		node.create_trimesh_collision()
	for child in node.get_children():
		if child is Node3D:
			add_tree_colliders(child)


func safe_ground(p: Vector3) -> bool:
	var point := Vector2(p.x, p.z)
	for polygon in blocked:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return false
	return Vector2(p.x - lone_tree.position.x, p.z - lone_tree.position.z).length() > 3.5


func spot() -> Vector3:
	for attempt in 40:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(5, 18)
		var p := lone_tree.position + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		p.y = park.ground_height(p.x, p.z)
		if safe_ground(p):
			return p
	return lone_tree.position + Vector3(8, 0, 0)


func make_animal(index: int, rabbit: bool) -> void:
	var root := Node3D.new()
	root.name = ("Rabbit" if rabbit else "Cat") + str(index)
	add_child(root)
	root.position = spot()
	var body := Node3D.new()
	root.add_child(body)
	var fur: String = (
		["d48a4c", "777c84", "e5d4ba"][index % 3]
		if not rabbit
		else ["e9dfd0", "b7a28b", "d9dce1"][index % 3]
	)
	part(body, Vector3(0, .35, 0), Vector3(.4, .4, .65), fur)
	part(body, Vector3(0, .56, .34), Vector3(.38, .35, .32), fur)
	var legs: Array[Node3D] = []
	for side in [-1, 1]:
		for z in [-.23, .23]:
			legs.append(part(body, Vector3(side * .15, .15, z), Vector3(.12, .28, .15), fur))
		var ear := part(
			body, Vector3(side * .12, .85, .32), Vector3(.11, .5 if rabbit else .19, .12), fur
		)
		part(ear, Vector3(0, 0, .062), Vector3(.05, .33 if rabbit else .09, .01), "d6a4a2")
		part(body, Vector3(side * .105, .6, .508), Vector3(.055, .07, .025), "202a25")
	part(body, Vector3(0, .49, .51), Vector3(.06, .05, .03), "c88d88")
	var tail := part(
		body,
		Vector3(0, .53, -.4),
		Vector3(.18, .18, .18) if rabbit else Vector3(.09, .09, .52),
		fur
	)
	if not rabbit:
		tail.rotation.x = -.55
	var animal := {
		"node": root,
		"body": body,
		"legs": legs,
		"tail": tail,
		"rabbit": rabbit,
		"goal": root.position,
		"rest": rng.randf_range(.3, 2.0),
		"phase": index * .8
	}
	animals.append(animal)
	targets.append({"node": root})


func advance(delta: float) -> void:
	clock += delta
	for a in animals:
		var node: Node3D = a.node
		if a.rest > 0:
			a.rest -= delta
			a.body.position.y = 0
			if a.rest <= 0:
				a.goal = spot()
			continue
		var offset: Vector3 = a.goal - node.position
		offset.y = 0
		if offset.length() < .3:
			a.rest = rng.randf_range(1, 4)
			continue
		var speed := 1.1 if a.rabbit else .7
		var next: Vector3 = (
			node.position + offset.normalized() * minf(speed * delta, offset.length())
		)
		if not safe_ground(next):
			a.rest = .5
			continue
		next.y = park.ground_height(next.x, next.z)
		node.position = next
		node.rotation.y = lerp_angle(node.rotation.y, atan2(offset.x, offset.z), minf(1, delta * 5))
		var phase: float = clock * (9 if a.rabbit else 6) + a.phase
		a.body.position.y = absf(sin(phase)) * .18 if a.rabbit else 0.0
		for i in a.legs.size():
			a.legs[i].rotation.x = sin(phase + i * PI) * .35
		a.tail.rotation.y = sin(phase * .4) * .25


func _process(delta: float) -> void:
	if is_instance_valid(sim) and (not sim.running or not sim.transport.connected()):
		return
	advance(minf(delta, .1))
