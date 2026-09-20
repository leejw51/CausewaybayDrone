extends CharacterBody3D

var spawn_position := Vector3(0, 7, 43)
var spawn_yaw := 0.0
var yaw := 0.0
var pitch := -0.25
var distance := 8.0
var visual: Node3D
var pivot: Node3D
var arm: SpringArm3D
var camera: Camera3D
var rotor_pivots: Array[Node3D] = []
var active := true
var ai_enabled := false
var ai_velocity := Vector3.ZERO
var flight_locked := false
var game: Node


func _ready() -> void:
	name = "Drone"
	collision_mask = 3
	position = spawn_position
	yaw = spawn_yaw
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.95
	shape.shape = sphere
	add_child(shape)
	visual = Node3D.new()
	add_child(visual)
	var model := preload("res://assets/coast_drone.glb").instantiate() as Node3D
	visual.add_child(model)
	model.scale = Vector3.ONE * 0.55
	model.position.y = -0.83
	# Blender's -Y nose becomes glTF +Z. Rotate the model to Godot's -Z forward.
	model.rotation.y = PI
	# Reparent each three-blade group around its motor for real rotor animation.
	var blades: Array[Node] = model.find_children("Propeller*", "MeshInstance3D", true, false)
	var motors: Array[Node] = model.find_children("Motor*", "MeshInstance3D", true, false)
	for motor in motors:
		var rotor := Node3D.new()
		model.add_child(rotor)
		rotor.global_position = motor.global_position
		rotor_pivots.append(rotor)
		for blade in blades:
			if (
				blade.get_parent() == model
				and (
					Vector2(blade.global_position.x, blade.global_position.z).distance_to(
						Vector2(motor.global_position.x, motor.global_position.z)
					)
					< 0.34
				)
			):
				blade.reparent(rotor, true)
	pivot = Node3D.new()
	add_child(pivot)
	pivot.position.y = 0.6
	arm = SpringArm3D.new()
	pivot.add_child(arm)
	arm.spring_length = distance
	arm.margin = 0.3
	arm.add_excluded_object(get_rid())
	camera = Camera3D.new()
	arm.add_child(camera)
	camera.current = true
	camera.fov = 64
	camera.far = 8000
	update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance - 1, 5, 23)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance + 1, 5, 23)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look_by(event.relative)
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event.is_action_pressed("reset_drone"):
		reset()
	update_camera()


func look_by(relative: Vector2) -> void:
	yaw -= relative.x * 0.003
	pitch = clampf(pitch - relative.y * 0.003, -1.15, 0.25)
	update_camera()


func update_camera() -> void:
	if pivot:
		pivot.rotation = Vector3(pitch, yaw, 0)
		arm.spring_length = distance


func reset() -> void:
	position = spawn_position
	velocity = Vector3.ZERO
	yaw = spawn_yaw
	pitch = -0.25
	distance = 8
	update_camera()


func _physics_process(delta: float) -> void:
	var stick := Input.get_vector("left", "right", "forward", "back") if active else Vector2.ZERO
	var rise := Input.get_axis("down", "up") if active else 0.0
	if ai_enabled and (stick.length() > .01 or absf(rise) > .01) and game:
		game.take_over()
	var direction := Basis(Vector3.UP, yaw) * Vector3(stick.x, 0, stick.y)
	var speed := 65.0 if Input.is_action_pressed("boost") else 22.0
	var target := direction * speed + Vector3.UP * rise * 8.0
	if ai_enabled:
		target = ai_velocity
	if flight_locked:
		target = Vector3.ZERO
	velocity = velocity.move_toward(target, 20 * delta)
	var incoming := velocity
	var previous_position := position
	move_and_slide()
	if get_slide_collision_count() > 0 and game:
		game.damage((incoming - velocity).length())
	var map: Node3D = get_parent().get_node("Park")
	if not map.flight_segment(previous_position, position):
		position = previous_position
		velocity = Vector3.ZERO
	var bounds: Rect2 = map.source_bounds
	position.x = clampf(position.x, bounds.position.x + 5, bounds.end.x - 5)
	position.z = clampf(position.z, bounds.position.y + 5, bounds.end.y - 5)
	position.y = clampf(position.y, map.ground_height(position.x, position.z) + 1.05, 650)
	var body_heading := yaw
	if ai_enabled and Vector2(velocity.x, velocity.z).length() > 1:
		body_heading = atan2(-velocity.x, -velocity.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, body_heading, 6 * delta)
	visual.rotation.x = lerpf(visual.rotation.x, stick.y * 0.13, 5 * delta)
	visual.rotation.z = lerpf(visual.rotation.z, -stick.x * 0.15, 5 * delta)
	for rotor in rotor_pivots:
		rotor.rotate_y(delta * (50 + velocity.length()))
