extends RefCounted
## Authored opening: park panorama, lone tree, rabbits, then live drone follow.
var active := false
var phase := 0
var elapsed := 0.0
var origin := Vector3.ZERO
var aim_origin := Vector3.ZERO
var aim := Vector3.ZERO
var rabbit: Node3D
var tree: Node3D
var drone_index := 0
const DURATIONS := [1.0, 1.0, 1.0, 2.0]
var destination := Vector3.ZERO
var destination_aim := Vector3.ZERO
var lift := 0.0
var follow_offset := Vector3(-5, 3.5, 10)


func roof(sim: Node, point: Vector3) -> float:
	# Include a near-plane margin, not just the camera center.
	var height: float = sim.top(point.x, point.z)
	for offset in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		height = maxf(height, sim.top(point.x + offset.x, point.z + offset.y))
	return height + 1.2


func plan(sim: Node) -> void:
	match phase:
		0:
			destination_aim = tree.global_position + Vector3.UP * 4
			destination = destination_aim + Vector3(20, 7, 28)
		1:
			destination_aim = rabbit.global_position + Vector3.UP * .55
			destination = destination_aim + Vector3(3.8, 1.3, 5.5)
		2:
			destination_aim = origin + Vector3(0, 12, -35)
			destination = origin + Vector3.UP * 65
		_:
			destination_aim = sim.vehicles[drone_index].node.global_position + Vector3.UP * 1.5
			destination = destination_aim + follow_offset
	destination.y = maxf(destination.y, roof(sim, destination))
	lift = 0
	# Plan above actual buildings/colliders, not just the terrain height map.
	var samples := maxi(32, int(origin.distance_to(destination) / 2.0))
	for i in range(1, samples):
		var u := float(i) / samples
		var point := origin.lerp(destination, u)
		lift = maxf(lift, (roof(sim, point) - point.y) / sin(PI * u))
	if phase == 3:
		lift = maxf(lift, 20.0)


func begin(sim: Node) -> void:
	if sim.park.wildlife.targets.is_empty() or sim.vehicles.is_empty():
		return
	tree = sim.park.wildlife.targets[0].node
	rabbit = tree
	for target in sim.park.wildlife.targets:
		if str(target.node.name).begins_with("Rabbit"):
			rabbit = target.node
			break
	drone_index = 0
	for i in sim.vehicles.size():
		if sim.vehicles[i].state not in ["IDLE", "CHARGING", "REPAIRING"]:
			drone_index = i
			break
	phase = 0
	elapsed = 0
	active = true
	sim.director = false
	sim.random_camera = false
	sim.free_camera = false
	sim.first_person = false
	origin = tree.global_position + Vector3(150, 110, 190)
	origin.y = maxf(origin.y, roof(sim, origin) + 30)
	aim = tree.global_position + Vector3.UP * 4
	aim_origin = aim
	sim.camera.global_position = origin
	sim.camera.look_at(aim)
	plan(sim)


func advance(sim: Node, delta: float) -> void:
	var remaining := maxf(delta, 0)
	while active and remaining > 0:
		var step := minf(remaining, float(DURATIONS[phase]) - elapsed)
		elapsed += step
		remaining -= step
		# Godot's tween curve drives translation, flight arc and aim together.
		var eased: float = Tween.interpolate_value(
			0.0, 1.0, elapsed, float(DURATIONS[phase]), Tween.TRANS_EXPO, Tween.EASE_IN_OUT
		)
		var endpoint := destination
		var target := destination_aim
		if phase == 3:
			target = sim.vehicles[drone_index].node.global_position + Vector3.UP * 1.5
			endpoint += target - destination_aim
			endpoint.y = maxf(endpoint.y, roof(sim, endpoint))
		var next := origin.lerp(endpoint, eased) + Vector3.UP * sin(PI * eased) * lift
		next.y = maxf(next.y, roof(sim, next))
		aim = aim_origin.lerp(target, eased)
		# Sweep between frames too: a thin wall must not be skipped at high speed.
		var query := PhysicsRayQueryParameters3D.create(sim.camera.global_position, next, 1)
		var hit: Dictionary = sim.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			next = hit.position + hit.normal * 1.2
			next.y = maxf(next.y, roof(sim, next))
		sim.camera.global_position = next
		if next.distance_squared_to(aim) > .01:
			sim.camera.look_at(aim)
		if elapsed >= float(DURATIONS[phase]) - .000001:
			phase += 1
			elapsed = 0
			origin = next
			aim_origin = aim
			if phase < DURATIONS.size():
				plan(sim)
			else:
				active = false
				sim.focus_kind = "drone"
				sim.focus_index = drone_index
				var offset := next - target
				sim.zoom = offset.length()
				sim.orbit = atan2(offset.x, offset.z)
				sim.elevation = asin(offset.y / offset.length())
				sim.follow_rig.reset(target, offset)
				sim.follow_subject = sim.vehicles[drone_index].node.get_instance_id()
				sim.ui.drone_list.select(drone_index)
