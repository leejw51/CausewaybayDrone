extends CharacterBody3D

var route := PackedVector3Array()
var waypoint := 0
var pace := 1.25
var phase := 0.0
var variant := 0
var limbs: Array[Node3D] = []
var hand_rest: Array[Vector3] = []
var body: Node3D
var distance_walked := 0.0
var gait := 0.0
var idle_time := 0.0
var celebrate := 0.0
var receiving := false
var holding := false
var working := false
var stay_near := false
var drinking := false
var disposing := false
var disposal_offset := Vector3(.6, 0, 0)
var consume_blend := 0.0
var stroll_offset := Vector3.ZERO
var stroll_clock := 0.0
var facing := 0.0
var receive_blend := 0.0
var knees: Array[Node3D] = []
var head: Node3D
var eyes: Array[Node3D] = []
var eye_scales: Array[Vector3] = []


func _ready() -> void:
	idle_time = variant * 1.73
	stroll_clock = variant * 2.37
	add_to_group("park_walkers")
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .32
	capsule.height = 1.95
	shape.shape = capsule
	shape.position.y = 1.0
	add_child(shape)
	body = Node3D.new()
	add_child(body)
	var models := [
		preload("res://assets/alex.glb"),
		preload("res://assets/mei.glb"),
		preload("res://assets/chef_bo.glb")
	]
	var model: Node3D = models[variant % models.size()].instantiate()
	body.add_child(model)
	model.rotation.y = PI
	for part in ["Leg_L", "Leg_R", "Arm_L", "Arm_R"]:
		limbs.append(model.find_child(part, true, false))

	for arm in [limbs[2], limbs[3]]:
		var hand: Array[Node] = arm.find_children("Hand*", "Node3D", true, false)
		hand_rest.append(
			arm.to_local(hand[0].global_position) if not hand.is_empty() else Vector3(0, -.295, .24)
		)
	for part in ["Knee_L", "Knee_R"]:
		knees.append(model.find_child(part, true, false))
	head = model.find_child("HeadPivot", true, false)
	for eye in model.find_children("*", "MeshInstance3D", true, false):
		if eye.name.begins_with("Eye") or eye.name.begins_with("Pupil"):
			eyes.append(eye)
			eye_scales.append(eye.scale)


func animate_character(delta: float, speed: float) -> void:
	idle_time += delta
	if route.size() < 2 and speed <= 0.0:
		stroll_clock += delta
		var lap := int(stroll_clock / 10.0)
		var walking := fmod(stroll_clock, 10.0) > 4.0
		var angle := float(lap) * 2.4 + float(variant) * 1.7
		var destination := Vector3(sin(angle), 0, cos(angle)) * .85
		if stay_near or receiving or holding or working or celebrate > 0:
			destination = Vector3.ZERO
		elif not walking:
			destination = stroll_offset
		if disposing:
			destination = disposal_offset
		var previous := stroll_offset
		stroll_offset = stroll_offset.move_toward(destination, delta * .42)
		var movement := stroll_offset - previous
		speed = movement.length() / maxf(delta, .0001)
		phase += movement.length() * 5.2
		if speed > .01 and not receiving and not holding:
			body.rotation.y = lerp_angle(
				body.rotation.y,
				atan2(-movement.x, -movement.z) - rotation.y,
				1.0 - exp(-4.0 * delta)
			)
		else:
			body.rotation.y = lerp_angle(body.rotation.y, 0.0, 1.0 - exp(-3.0 * delta))
	celebrate = maxf(0.0, celebrate - delta)
	var consume_target := 0.0
	if holding and celebrate <= 0.0 and not disposing:
		consume_target = smoothstep(.1, .7, sin(idle_time * 1.6))
	consume_blend = lerpf(consume_blend, consume_target, 1.0 - exp(-5.0 * delta))
	if route.size() < 2 and not working:
		rotation.y = lerp_angle(rotation.y, facing, 1.0 - exp(-5.0 * delta))
	gait = lerpf(gait, clampf(speed / maxf(pace, .1), 0, 1), 1.0 - exp(-8.0 * delta))
	receive_blend = lerpf(
		receive_blend, 1.0 if receiving or holding else 0.0, 1.0 - exp(-6.0 * delta)
	)
	body.position.y = absf(sin(phase)) * .022 * gait + sin(idle_time * 1.8) * .004 * (1.0 - gait)
	body.rotation.z = sin(phase) * .018 * gait
	# Small weight shifts stay inside the receiving area; hands share this transform.
	if route.size() < 2:
		var idle_weight := 1.0 - receive_blend
		body.position.x = stroll_offset.x + sin(idle_time * .65 + variant) * .06 * idle_weight
		body.position.z = stroll_offset.z + sin(idle_time * .43 + variant) * .04 * idle_weight
		body.rotation.z += sin(idle_time * 1.1) * .025 * idle_weight
	if celebrate > 0.0:
		body.position.y += absf(sin(celebrate * 5.0)) * .09 * minf(celebrate, 1.0)
		body.rotation.z += sin(celebrate * 5.0) * .045
	for i in 2:
		var cycle := phase + PI * i
		limbs[i].rotation.x = sin(cycle) * .36 * gait
		knees[i].rotation.x = maxf(0, sin(cycle + .7)) * .48 * gait
		var swing := -sin(cycle) * .24 * gait
		limbs[i + 2].rotation.x = lerpf(
			swing, -.95 - consume_blend * .65 + sin(idle_time * 2) * .025, receive_blend
		)
		if holding:
			var grip := Vector3(0, 1.15, -.30).lerp(
				Vector3(0, 1.30 if not drinking else 1.23, -.30), consume_blend
			)
			var arm: Node3D = limbs[i + 2]
			var local_grip: Vector3 = arm.get_parent().to_local(body.to_global(grip)) - arm.position
			var pose := Quaternion(hand_rest[i].normalized(), local_grip.normalized())
			arm.quaternion = arm.quaternion.slerp(pose, receive_blend)
		if working:
			limbs[i + 2].rotation.x = -0.8 + sin(idle_time * 2.6 + i * PI) * .3
	head.rotation.y = sin(idle_time * .65 + variant) * .10 * (1.0 - receive_blend)
	head.rotation.x = (
		sin(idle_time * .9) * .025
		- receive_blend * .10
		+ consume_blend * (-.12 if drinking else .12)
	)
	if celebrate > 0.0:
		head.rotation.x += sin(celebrate * 6.0) * .16
	var blink_phase := fmod(idle_time + variant * .73, 4.3)
	var blink := 1.0 - .92 * sin(clampf(blink_phase / .16, 0, 1) * PI) if blink_phase < .16 else 1.0
	for i in eyes.size():
		eyes[i].scale = eye_scales[i] * Vector3(1, blink, 1)


func _physics_process(delta: float) -> void:
	if route.size() < 2:
		animate_character(delta, 0)
		return
	var target := route[waypoint] - position
	target.y = 0
	if target.length() < .35:
		waypoint = (waypoint + 1) % route.size()
		target = route[waypoint] - position
		target.y = 0
	var direction := target.normalized()
	var weight := 1.0 - exp(-5.0 * delta)
	velocity.x = lerpf(velocity.x, direction.x * pace, weight)
	velocity.z = lerpf(velocity.z, direction.z * pace, weight)
	velocity.y = -1.0 if is_on_floor() else velocity.y - 12.0 * delta
	var before := position
	move_and_slide()
	var travelled := Vector2(position.x - before.x, position.z - before.z).length()
	distance_walked += travelled
	phase += travelled * 5.2
	if travelled > .0001:
		body.rotation.y = lerp_angle(
			body.rotation.y, atan2(-velocity.x, -velocity.z), 1.0 - exp(-7.0 * delta)
		)
	animate_character(delta, travelled / maxf(delta, .0001))
