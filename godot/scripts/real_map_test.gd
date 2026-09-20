extends RefCounted


func run(main: Node3D) -> void:
	var tree := main.get_tree()
	tree.create_timer(35).timeout.connect(func(): tree.quit(1))
	var park: Node3D = main.park
	var drone: CharacterBody3D = main.drone
	assert(park.data.buildings.size() > 1500, "Building import incomplete")
	assert(park.data.roads.size() > 1500, "Road import incomplete")
	assert(park.data.water.size() == 9, "Water import incomplete")
	assert(park.water_nodes.size() == 9, "Water shader surfaces missing")
	for water in park.water_nodes:
		assert(water.material_override is ShaderMaterial, "Water must use the spatial shader")
		assert(
			water.material_override.shader.resource_path == "res://assets/lake_water.gdshader",
			"Incorrect water shader"
		)
	var kspo: Dictionary = park.landmark("KSPO DOME")
	var lotte: Dictionary = park.landmark("LOTTE WORLD TOWER")
	var hotel: Dictionary = park.landmark("SEOUL OLYMPIC PARKTEL")
	assert(
		kspo.position[0] > 1000 and kspo.position[2] < 0,
		"KSPO must be over a kilometre east of gate"
	)
	assert(
		lotte.position[0] < -1000 and lotte.position[2] > 600,
		"Lotte must be southwest at real distance"
	)
	assert(lotte.height == 555 and hotel.height == 68, "Mapped heights must not be compressed")
	# Independent great-circle distance checks the metre-scale projection.
	var origin: Dictionary = park.data.origin
	var p1 := deg_to_rad(float(origin.lat))
	var p2 := deg_to_rad(float(kspo.lat))
	var dl := deg_to_rad(float(kspo.lon) - float(origin.lon))
	var hav := pow(sin((p2 - p1) / 2), 2) + cos(p1) * cos(p2) * pow(sin(dl / 2), 2)
	var geodesic := 6371008.8 * 2 * atan2(sqrt(hav), sqrt(1 - hav))
	var metres := Vector2(kspo.position[0], kspo.position[2]).length()
	assert(absf(geodesic - metres) < 4, "Projection distance differs from geodesic")
	await tree.physics_frame
	var start := drone.position
	Input.action_press("forward")
	for i in range(60):
		await tree.physics_frame
	Input.action_release("forward")
	assert(drone.position.distance_to(start) > 4, "Movement failed")
	Input.action_press("up")
	for i in range(60):
		await tree.physics_frame
	Input.action_release("up")
	assert(drone.position.y > start.y + 3, "Climb failed")
	for i in range(70):
		await tree.physics_frame
	assert(drone.velocity.length() < .1, "Hover braking failed")
	var y: float = drone.yaw
	drone.look_by(Vector2(100, 40))
	assert(drone.yaw < y - .2, "Mouse yaw failed")
	drone.reset()
	assert(drone.position.is_equal_approx(drone.spawn_position), "Reset failed")
	assert(drone.rotor_pivots.size() == 6, "Rotor animation missing")
	var center: Vector3 = park.vec(kspo.position)
	var query := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 100, center, 1)
	var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(query)
	assert(not hit.is_empty(), "Mapped stadium collision missing")
	assert(float(hit.position.y) > center.y + 15, "Ray hit terrain instead of stadium")
	var visitors := tree.get_nodes_in_group("park_walkers")
	assert(visitors.size() == 32, "Visitors missing")
	var moving := 0
	for person in visitors:
		if person.distance_walked > 1:
			moving += 1
	assert(moving >= 28, "Visitors should walk on mapped paths")
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	drone.position = park.delivery_point
	main._unhandled_input(event)
	assert(main.hud.delivered, "Delivery waypoint failed")
	drone.position = park.rescue_point
	main._unhandled_input(event)
	assert(main.hud.rescued, "Rescue waypoint failed")
	print(
		"REAL_MAP_SMOKE_OK: metre-scale projection, real bearings, mapped heights, terrain/building collision, flight, walkers, missions"
	)
	tree.quit()
