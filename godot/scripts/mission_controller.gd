extends Node

enum Phase { BRIEFING, FLIGHT, SERVICE, RETURNING, DOCKED, COMPLETE, FAILED }
var phase := Phase.BRIEFING
var drone: CharacterBody3D
var park: Node3D
var missions: Array[Dictionary] = []
var mission_index := 0
var battery := 100.0
var integrity := 100.0
var score := 0
var elapsed := 0.0
var service_time := 0.0
var ai := false
var status := "Ready for dispatch"
var navigation := "STANDBY"
var route := PackedVector3Array()
var route_index := 0
var home := Vector3.ZERO
var damage_cooldown := 0.0
var marker: Node3D
var effects: Node3D
var active := true
var completed_count := 0
var minimum_battery := 100.0
var emergency_return := false
var campaign: Array[Dictionary] = []
var order: Dictionary = {}
var order_serial := 0
const MENU = ["Sandwich", "Coffee", "Sandwich + Coffee"]


func place_order(item: int, quantity: int) -> bool:
	if (
		not active
		or phase != Phase.BRIEFING
		or item < 0
		or item >= MENU.size()
		or quantity < 1
		or quantity > 3
	):
		return false
	order_serial += 1
	order = {
		"id": order_serial, "item": MENU[item], "quantity": quantity, "state": "OUT FOR DELIVERY"
	}
	missions = [
		{
			"title": "Order #%03d" % order_serial,
			"detail": "%d x %s" % [quantity, MENU[item]],
			"target": park.delivery_point,
			"seconds": 3.0,
			"points": 300 * quantity,
			"kind": "delivery"
		}
	]
	begin(true)
	status = "Order #%03d accepted — %d x %s" % [order_serial, quantity, MENU[item]]
	return true


func _ready() -> void:
	process_physics_priority = -10
	if active:
		drone.flight_locked = true
	home = Vector3(
		drone.spawn_position.x,
		park.ground_height(drone.spawn_position.x, drone.spawn_position.z) + 1.1,
		drone.spawn_position.z
	)
	var rescue: Vector3 = park.rescue_point
	var best := INF
	for water in park.data.water:
		if int(water.id) != 6968154:
			continue
		for i in range(0, water.triangles.size(), 3):
			var p: Vector3 = (
				(
					park.vec(water.triangles[i])
					+ park.vec(water.triangles[i + 1])
					+ park.vec(water.triangles[i + 2])
				)
				/ 3
			)
			var d := Vector2(p.x - rescue.x, p.z - rescue.z).length()
			if d < best:
				best = d
				park.rescue_point = p + Vector3.UP * 3.0
	var dome: Dictionary = park.landmark("KSPO DOME")
	var survey: Vector3 = park.vec(dome.position) + Vector3.UP * (float(dome.height) + 12)
	missions = [
		{
			"title": "Lunch delivery",
			"detail": "Deliver the sandwich and coffee",
			"target": park.delivery_point,
			"seconds": 3.0,
			"points": 300,
			"kind": "delivery"
		},
		{
			"title": "Lakeside rescue",
			"detail": "Deploy flotation equipment over Mongchon Lake",
			"target": park.rescue_point,
			"seconds": 4.0,
			"points": 500,
			"kind": "rescue"
		},
		{
			"title": "Stadium inspection",
			"detail": "Hold position above KSPO Dome and scan the roof",
			"target": survey,
			"seconds": 4.0,
			"points": 400,
			"kind": "survey"
		}
	]
	campaign = missions.duplicate(true)
	effects = Node3D.new()
	effects.name = "MissionEffects"
	park.add_child(effects)
	create_marker()
	create_pad()


func target() -> Vector3:
	return (
		home
		if phase == Phase.RETURNING or phase == Phase.DOCKED or mission_index >= missions.size()
		else missions[mission_index].target
	)


func in_progress() -> bool:
	return phase in [Phase.FLIGHT, Phase.SERVICE, Phase.RETURNING]


func begin(use_ai := true) -> void:
	if not active:
		return
	if phase in [Phase.COMPLETE, Phase.FAILED]:
		restart()
	if phase == Phase.DOCKED and battery < 30:
		status = "Charging at base — wait until battery reaches 30%"
		return
	ai = use_ai
	drone.ai_enabled = ai
	drone.flight_locked = false
	phase = Phase.FLIGHT
	status = "Deliver lunch to the marked waypoint"
	service_time = 0
	if ai:
		plan_route(target())
	else:
		status = "Manual flight — hold F at the waypoint to service"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func restart() -> void:
	ai = false
	drone.ai_enabled = false
	drone.flight_locked = true
	drone.ai_velocity = Vector3.ZERO
	drone.reset()
	phase = Phase.BRIEFING
	order = {}
	missions = campaign.duplicate(true)
	battery = 100
	integrity = 100
	score = 0
	elapsed = 0
	service_time = 0
	mission_index = 0
	completed_count = 0
	minimum_battery = 100
	emergency_return = false
	route.clear()
	status = "Ready for dispatch"
	navigation = "STANDBY"
	for node in effects.get_children():
		node.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func take_over() -> void:
	if not ai:
		return
	ai = false
	drone.ai_enabled = false
	status = "Manual takeover — TAB re-engages AI"
	navigation = "MANUAL"


func toggle_ai() -> void:
	if phase in [Phase.BRIEFING, Phase.DOCKED]:
		begin(true)
		return
	if phase in [Phase.COMPLETE, Phase.FAILED]:
		return
	if ai:
		take_over()
	else:
		ai = true
		drone.ai_enabled = true
		plan_route(target())
		status = "AI flight resumed"


func return_home() -> void:
	if not in_progress():
		return
	phase = Phase.RETURNING
	service_time = 0
	ai = true
	drone.ai_enabled = true
	plan_route(home)
	status = "Returning to base for landing and recharge"


func ray_top(x: float, z: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(x, 645, z), Vector3(x, -100, z), 1, [drone.get_rid()]
	)
	var result: Dictionary = drone.get_world_3d().direct_space_state.intersect_ray(query)
	return result.position.y if not result.is_empty() else park.ground_height(x, z)


func plan_route(destination: Vector3) -> void:
	var start := drone.position
	var length := Vector2(start.x - destination.x, start.z - destination.z).length()
	var count := maxi(2, ceili(length / 10))
	var cruise := maxf(start.y, destination.y) + 18
	for i in range(count + 1):
		var p := start.lerp(destination, float(i) / count)
		cruise = maxf(cruise, ray_top(p.x, p.z) + 16)
	cruise = minf(cruise, 625)
	route = PackedVector3Array(
		[
			Vector3(start.x, cruise, start.z),
			Vector3(destination.x, cruise, destination.z),
			destination
		]
	)
	route_index = 0
	navigation = "CLIMB"


func clearance(motion: Vector3) -> float:
	var sphere := SphereShape3D.new()
	sphere.radius = 1.65
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, drone.position)
	q.motion = motion
	q.collision_mask = 3
	q.exclude = [drone.get_rid()]
	var result := drone.get_world_3d().direct_space_state.cast_motion(q)
	return result[0] if result.size() > 0 else 1.0


func follow_route(delta: float) -> void:
	if route.is_empty():
		plan_route(target())
	var point := route[route_index]
	var offset := point - drone.position
	if offset.length() < 1.3 and drone.velocity.length() < 2 and route_index < route.size() - 1:
		route_index += 1
		point = route[route_index]
		offset = point - drone.position
	var cruise_speed := 32.0 if route_index == 1 else 9.0
	var speed := minf(cruise_speed, sqrt(maxf(offset.length() - .2, 0) * 2 * 10))
	drone.ai_velocity = offset.normalized() * speed
	navigation = ["CLIMB", "CRUISE", "APPROACH"][route_index]
	if route_index == 1:
		var lookahead := offset.normalized() * maxf(8, drone.velocity.length_squared() / 32 + 5)
		if clearance(lookahead) < .98:
			if clearance(Vector3.UP * 12) > .98 and drone.position.y < 610:
				drone.ai_velocity = Vector3.UP * 7
				route[1].y = maxf(route[1].y, drone.position.y + 10)
				navigation = "AVOID / CLIMB"
			else:
				drone.ai_velocity = Vector3.ZERO
				navigation = "OBSTACLE / HOLD"
				status = "Path obstructed — hovering; TAB for manual takeover"
	# Dwell checks run after the movement update on the following frame.
	if delta <= 0:
		drone.ai_velocity = Vector3.ZERO


func damage(impact: float) -> void:
	if not in_progress() or damage_cooldown > 0 or impact < 4:
		return
	integrity = maxf(0, integrity - (impact - 3) * 2.5)
	score = maxi(0, score - 25)
	damage_cooldown = .8
	status = "Collision — hull damaged"
	if integrity <= 0:
		fail("Aircraft damaged beyond mission limits")


func fail(reason: String) -> void:
	if not order.is_empty() and order.state != "DELIVERED":
		order.state = "DELIVERY FAILED"
	phase = Phase.FAILED
	ai = false
	drone.ai_enabled = false
	drone.flight_locked = true
	drone.velocity = Vector3.ZERO
	status = reason
	navigation = "ABORTED"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if not active:
		return
	damage_cooldown = maxf(0, damage_cooldown - delta)
	marker.visible = in_progress()
	if marker.visible:
		marker.position = target()
		marker.rotation.y += delta * .35
	if phase == Phase.DOCKED:
		battery = minf(100, battery + 12 * delta)
		integrity = minf(100, integrity + 6 * delta)
		return
	if not in_progress():
		return
	elapsed += delta
	battery = maxf(
		0, battery - delta * (.045 + drone.velocity.length() * .007 + absf(drone.velocity.y) * .01)
	)
	minimum_battery = minf(minimum_battery, battery)
	if battery <= 0:
		fail("Battery depleted — restart the sortie with R")
		return
	if battery < 20 and phase != Phase.RETURNING:
		emergency_return = true
		return_home()
		status = "Low battery — automatic return to base"
	if ai:
		follow_route(delta)
	var close := drone.position.distance_to(target()) < 2.5 and drone.velocity.length() < 1.25
	if phase == Phase.RETURNING:
		if close:
			service_time += delta
			if service_time > 1.5:
				ai = false
				drone.ai_enabled = false
				drone.flight_locked = true
				drone.velocity = Vector3.ZERO
				if mission_index >= missions.size():
					phase = Phase.COMPLETE
					score += roundi(battery * 2 + integrity)
					status = "All missions complete — aircraft recovered"
				else:
					phase = Phase.DOCKED
					status = "Docked — recharging; ENTER resumes the mission"
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			service_time = 0
		return
	if close and (ai or Input.is_action_pressed("interact")):
		phase = Phase.SERVICE
		service_time += delta
		navigation = "SERVICE / HOVER"
		if service_time >= float(missions[mission_index].seconds):
			complete_task()
	else:
		phase = Phase.FLIGHT
		service_time = 0


func complete_task() -> void:
	var mission: Dictionary = missions[mission_index]
	deploy_effect(mission.kind, target())
	if not order.is_empty():
		order.state = "DELIVERED"
	score += int(mission.points)
	completed_count += 1
	mission_index += 1
	service_time = 0
	route.clear()
	if mission_index >= missions.size():
		return_home()
	else:
		phase = Phase.FLIGHT
		status = "Task complete — next: " + str(missions[mission_index].title)
		if ai:
			plan_route(target())


func deploy_effect(kind: String, p: Vector3) -> void:
	if kind == "survey":
		return
	var node := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("f59845")
	if kind == "rescue":
		var ring := TorusMesh.new()
		ring.inner_radius = .42
		ring.outer_radius = .7
		node.mesh = ring
	else:
		var box := BoxMesh.new()
		box.size = Vector3(.65, .4, .55)
		node.mesh = box
	node.material_override = mat
	effects.add_child(node)
	node.position = drone.position - Vector3.UP * .6
	var landing := (
		Vector3(p.x, p.y - 2.8, p.z)
		if kind == "rescue"
		else Vector3(p.x, park.ground_height(p.x, p.z) + .25, p.z)
	)
	create_tween().tween_property(node, "position", landing, 1.3).set_trans(Tween.TRANS_SINE)


func create_marker() -> void:
	marker = Node3D.new()
	park.add_child(marker)
	var mesh := TorusMesh.new()
	mesh.inner_radius = 2.8
	mesh.outer_radius = 3
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("86e0bd")
	mat.emission_enabled = true
	mat.emission = Color("4bba91")
	node.material_override = mat
	marker.add_child(node)
	marker.visible = false


func create_pad() -> void:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 3.5
	mesh.bottom_radius = 3.5
	mesh.height = .12
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("267d79")
	node.material_override = mat
	park.add_child(node)
	node.position = home - Vector3.UP
