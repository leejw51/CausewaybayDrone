extends Node3D
const FOOD = [preload("res://assets/sandwich.glb"), preload("res://assets/coffee.glb")]
const AIRCRAFT = preload("res://assets/coast_drone.glb")
var locale := "en"
var park: Node3D
var camera: Camera3D
var config := {"drones": 8, "cafes": 3, "humans": 20, "mode": "Massive"}
var vehicles: Array[Dictionary] = []
var cafes: Array[Dictionary] = []
var docks: Array[Dictionary] = []
var humans: Array[Dictionary] = []
var orders: Array[Dictionary] = []
var state: Dictionary = {}
var world: Node3D
var ui: Control
var sound_effects: Node3D
var selected_hud: Control
var game_effects: Node3D
var opening_rig := preload("res://scripts/opening_camera.gd").new()
var random_camera := false
var random_rig := preload("res://scripts/random_camera.gd").new()
var director := false
var director_timer := 0.0
var director_cursor := 0
var running := false
var sim_time := 0.0
var storage_error := "Connecting to Rust backend..."
var focus_kind := "cafe"
var focus_index := 0
var first_person := false
var presentation_time_scale := clampf(float(OS.get_environment("COAST_TEST_SPEED")), 1.0, 40.0)
var follow_rig := preload("res://scripts/follow_camera_rig.gd").new()
var follow_subject := 0
var free_camera := false
var free_speed := 18.0
var free_velocity := Vector3.ZERO
var orbit_dragging := false
var orbit_returning := false
var orbit_home := Vector2.ZERO
var orbit_release := Vector2.ZERO
var orbit_return_time := 0.0
const ORBIT_RETURN_SECONDS := 1.4
var orbit := -.4
var elevation := .42
var zoom := 18.0
var transport: RefCounted
var retry := 0.0
var motion_seconds := 0.0
var motion_frames := 0
var motion_stalls := 0
var motion_reported := false
var built_run := ""
var receipts: Dictionary = {}
var speech := true
var voices: PackedStringArray = []
var backend_pid := -1
var last_revision := -1
var server_id := ""
var start_after_config := false
var pending_run := "--none"
var error_until := 0
var backend_url := "ws://127.0.0.1:8799"


func _ready() -> void:
	preload("res://scripts/localization.gd").install()
	name = "FleetSimulator"
	camera.reparent(self, true)
	camera.set_as_top_level(true)
	if not OS.get_environment("COAST_WS").is_empty():
		backend_url = OS.get_environment("COAST_WS")
	transport = ClassDB.instantiate("CoastTransport")
	transport.connect_backend(backend_url)
	ui = preload("res://scripts/fleet_ui.gd").new()
	ui.sim = self
	get_parent().get_node("CanvasLayer").add_child(ui)
	sound_effects = preload("res://scripts/sound_effects.gd").new()
	sound_effects.sim = self
	add_child(sound_effects)
	game_effects = preload("res://scripts/game_effects.gd").new()
	game_effects.sim = self
	add_child(game_effects)
	var mission_hud := preload("res://scripts/mission_hud.gd").new()
	mission_hud.sim = self
	get_parent().get_node("CanvasLayer").add_child(mission_hud)
	selected_hud = preload("res://scripts/selected_drone_hud.gd").new()
	selected_hud.sim = self
	get_parent().get_node("CanvasLayer").add_child(selected_hud)
	voices = DisplayServer.tts_get_voices_for_language("en")
	get_tree().auto_accept_quit = false
	if "--autonomous" in OS.get_cmdline_user_args():
		autonomous_start.call_deferred()
	if "--fleet-gallery" in OS.get_cmdline_user_args():
		gallery.call_deferred()
	if "--fleet-test" in OS.get_cmdline_user_args():
		test_fleet.call_deferred()


func send(command: Dictionary) -> void:
	if not transport.connected():
		storage_error = "Backend disconnected — reconnecting"
		return
	transport.send_json(JSON.stringify(command))


func configure(d: int, c: int, h: int, mode: String, auto_orders: bool = true) -> void:
	if running:
		storage_error = "Stop simulation before changing counts"
		return
	if not transport.connected():
		storage_error = "Wait for the backend connection"
		return
	if mode == "Solo":
		d = 1
		c = 1
		h = 1
	pending_run = state.get("run_id", "")
	config = {
		"drones": clampi(d, 1, 32),
		"cafes": clampi(c, 1, 12),
		"humans": clampi(h, 1, 200),
		"mode": mode,
		"auto_orders": auto_orders,
		"language": locale,
		"sfx_enabled": config.get("sfx_enabled", true),
		"sfx_volume": config.get("sfx_volume", .65)
	}
	build_world()
	var layout := {"homes": [], "pickups": [], "customers": [], "windows": [], "interiors": []}
	for v in vehicles:
		layout.homes.append(arr(v.home))
	for cafe in cafes:
		layout.pickups.append(arr(cafe.pickup))
	for human in humans:
		layout.customers.append(arr(human.point))
		layout.windows.append(arr(human.node.position + Vector3(0, 9.8, 10)))
		layout.interiors.append(arr(human.node.position + Vector3(0, 9.8, 2)))
	send({"command": "configure", "config": config, "layout": layout})


func place_order(item: String, quantity: int, human: int, cafe: int, apartment: bool) -> void:
	send(
		{
			"command": "order",
			"item": item,
			"quantity": quantity,
			"human": human,
			"cafe": cafe,
			"apartment": apartment
		}
	)


func vec(p: Array) -> Vector3:
	return Vector3(p[0], p[1], p[2])


func arr(p: Vector3) -> Array:
	return [p.x, p.y, p.z]


func material(hex: String) -> StandardMaterial3D:
	return preload("res://scripts/toy_material.gd").create(Color(hex))


func box(parent: Node3D, p: Vector3, s: Vector3, color: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = s
	node.mesh = mesh
	node.material_override = material(color)
	parent.add_child(node)
	node.position = p
	return node


func label(parent: Node3D, p: Vector3, title: String) -> Label3D:
	var l := Label3D.new()
	l.text = title
	l.font = preload("res://assets/fonts/game-ui.tres")
	l.font_size = 28
	l.pixel_size = .008
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.outline_size = 8
	parent.add_child(l)
	l.position = p
	return l


func top(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 645, z), Vector3(x, -100, z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else park.ground_height(x, z)


func land(seed: Vector3) -> Vector3:
	if not park.in_flight_area(seed):
		seed = Vector3(400, 0, -250)
	for i in range(100):
		var p := seed + Vector3(cos(i * 2.4), 0, sin(i * 2.4)) * sqrt(float(i)) * 3
		var contained := true
		for offset in [
			Vector3.ZERO,
			Vector3(14, 0, 0),
			Vector3(-14, 0, 0),
			Vector3(0, 0, 14),
			Vector3(0, 0, -14)
		]:
			contained = contained and park.in_flight_area(p + offset)
		if not contained:
			continue
		var ground: float = park.ground_height(p.x, p.z)
		if absf(top(p.x, p.z) - ground) > .8:
			continue
		var wet := false
		for water in park.data.water:
			var ring := PackedVector2Array()
			for v in water.rings[0]:
				ring.append(Vector2(v[0], v[1]))
			if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), ring):
				wet = true
				break
		if not wet:
			return Vector3(p.x, ground, p.z)
	return Vector3(seed.x, top(seed.x, seed.z), seed.z)


func shop_name(index: int) -> String:
	var names := [
		"Park Kitchen", "Lake Cafe", "Garden Deli", "Sunrise Kitchen", "Green Cafe", "Sky Deli"
	]
	return tr("%02d / %s") % [index + 1, names[index % names.size()]]


func customer_name(index: int) -> String:
	var names := ["Alex", "Mei", "Chef Bo", "Alex", "Mei", "Chef Bo"]
	return tr("%02d / %s") % [index + 1, names[index % names.size()]]


func build_world() -> void:
	if world:
		remove_child(world)
		world.queue_free()
	world = Node3D.new()
	add_child(world)
	var engineer := preload("res://assets/rust-coder.glb").instantiate()
	world.add_child(engineer)
	engineer.position = land(Vector3(117, 0, -53))
	label(engineer, Vector3(0, 2.15, 0), "Causewaybay Rust Coder / FIELD ENGINEER")
	vehicles.clear()
	docks.clear()
	cafes.clear()
	humans.clear()
	for i in int(config.cafes):
		var p := land(Vector3(130 + i * 23, 0, -130))
		var node := Node3D.new()
		world.add_child(node)
		node.position = p
		box(node, Vector3(0, .12, 0), Vector3(9, .24, 7), "d8c7a1")
		box(node, Vector3(0, 1.3, -1.6), Vector3(5, 2.6, .2), "216b61")
		box(node, Vector3(0, 1.1, .3), Vector3(5, 1.1, 1.0), "ebd7ac")
		box(
			node,
			Vector3(0, 3.2, 0),
			Vector3(7, .22, 5),
			["e7a04c", "59b8ac", "cf7882", "7c9bc2"][i % 4]
		)
		for x in [-3.0, 3.0]:
			box(node, Vector3(x, 1.6, -1.5), Vector3(.18, 3.2, .18), "345c58")
		var sign := label(node, Vector3(0, 3.9, 0), shop_name(i) + tr(" / ROBOT KITCHEN"))
		var light := OmniLight3D.new()
		node.add_child(light)
		light.position = Vector3(0, 2.8, 1)
		light.omni_range = 8
		light.light_energy = 1.5
		light.light_color = Color("ffe2b8")
		var robot: Node3D = preload("res://assets/cb-robot.glb").instantiate()
		node.add_child(robot)
		robot.position = Vector3(0, .24, -.4)
		var arms: Array[Node3D] = []
		for shoulder_name in ["Shoulder_L", "Shoulder_R"]:
			var arm: Node3D = robot.find_child(shoulder_name, true, false)
			if arm:
				arms.append(arm)
		var owner := CharacterBody3D.new()
		owner.set_script(preload("res://scripts/walker.gd"))
		owner.variant = 2
		node.add_child(owner)
		owner.position = Vector3(2.1, .24, -.3)
		owner.rotation.y = PI
		owner.set_physics_process(false)
		var food := meal("Sandwich + Coffee", 1)
		node.add_child(food)
		food.position = Vector3(0, 1.68, .3)
		food.visible = false
		# Robot-fed conveyor ends directly beneath the drone docking position.
		box(node, Vector3(0, 1.57, 2.9), Vector3(1.05, .16, 5.6), "344c51")
		for z in range(12):
			box(node, Vector3(0, 1.665, .3 + z * .46), Vector3(.95, .025, .06), "8daaaa")
		for z in [1.0, 5.5]:
			box(node, Vector3(0, .8, z), Vector3(.18, 1.6, .18), "627c7b")
		var lift := Node3D.new()
		node.add_child(lift)
		lift.position = Vector3(0, 1.68, 5.5)
		box(lift, Vector3(0, -.08, 0), Vector3(1.1, .12, .8), "e4a04b")
		box(node, Vector3(.68, 1.6, 5.5), Vector3(.12, 3.2, .12), "627c7b")
		var pickup: Vector3 = p + Vector3(0, 3.8, 5.5)
		box(node, Vector3(0, .18, 5.5), Vector3(4, .15, 3), "3ba895")
		var info := label(node, Vector3(0, 4.65, 0), tr("WAITING FOR ORDERS"))
		cafes.append(
			{
				"node": node,
				"arms": arms,
				"robot": robot,
				"owner": owner,
				"food": food,
				"food_job": -1,
				"sign": sign,
				"lift": lift,
				"label": info,
				"pickup": pickup,
				"job": -1,
				"timer": 0.0
			}
		)
	for i in int(config.humans):
		var p := land(Vector3(300 + (i % 10) * 14, 0, -200 - (i / 10) * 16))
		var person := CharacterBody3D.new()
		person.set_script(preload("res://scripts/walker.gd"))
		person.variant = i
		world.add_child(person)
		person.position = p
		person.set_physics_process(false)
		var bin: Node3D = preload("res://assets/park-litter-bin.glb").instantiate()
		world.add_child(bin)
		bin.position = p + Vector3(1.25, 0, 0)
		var info := label(person, Vector3(0, 3.3, 0), customer_name(i) + "\n" + tr("WAITING"))
		humans.append(
			{
				"node": person,
				"label": info,
				"point": p + Vector3(0, 3.5, -2),
				"received": 0,
				"active_order": -1,
				"held": null,
				"hold_until": 0.0,
				"meal_clock": 0.0,
				"meal_kind": "Sandwich",
				"trash_clock": -1.0,
				"bin": bin,
				"base": p,
				"apartment": null
			}
		)
	for i in int(config.drones):
		var node := Node3D.new()
		world.add_child(node)
		var model := AIRCRAFT.instantiate()
		node.add_child(model)
		model.scale = Vector3.ONE * .55
		model.position.y = -.83
		# Remove baked display food: actual order models are loaded at the cafe.
		for part in model.find_children("*", "MeshInstance3D", true, false):
			if "Sandwich" in part.name or "coffee" in part.name.to_lower():
				part.visible = false
		var rotors: Array[Node3D] = []
		var blades := model.find_children("Propeller*", "MeshInstance3D", true, false)
		for motor in model.find_children("Motor*", "MeshInstance3D", true, false):
			var rotor := Node3D.new()
			model.add_child(rotor)
			rotor.global_position = motor.global_position
			rotors.append(rotor)
			for blade in blades:
				if (
					blade.get_parent() == model
					and (
						Vector2(blade.global_position.x, blade.global_position.z).distance_to(
							Vector2(motor.global_position.x, motor.global_position.z)
						)
						< .34
					)
				):
					blade.reparent(rotor, true)
		var p := land(Vector3(130 + (i % 6) * 9, 0, -40 - (i / 6) * 9)) + Vector3.UP * 2
		node.position = p
		box(world, p - Vector3.UP * 1.8, Vector3(4, .12, 4), "287971")
		var dock := Node3D.new()
		world.add_child(dock)
		dock.position = p
		box(dock, Vector3(2, -.65, 0), Vector3(.5, 2.4, .7), "45616e")
		box(dock, Vector3(2, .35, .36), Vector3(.35, .3, .03), "73efb3")
		var cable := box(dock, Vector3(1.2, -.5, 0), Vector3(1.6, .09, .09), "edc457")
		var arm := Node3D.new()
		dock.add_child(arm)
		arm.position = Vector3(-2, -.7, 0)
		box(arm, Vector3(.5, 0, 0), Vector3(1, .18, .18), "e5a14b")
		box(arm, Vector3(1, .4, 0), Vector3(.18, .8, .18), "e5a14b")
		box(arm, Vector3(1.2, .8, 0), Vector3(.5, .2, .35), "879ba5")
		var dock_label := label(dock, Vector3(0, -.8, 2.5), "")
		docks.append({"node": dock, "arm": arm, "cable": cable, "label": dock_label})
		var info := label(node, Vector3(0, 3, 0), tr("DRONE %02d / IDLE") % (i + 1))
		box(node, Vector3(0, .3, .72), Vector3(.88, .5, .1), "172b32")
		var face := label(node, Vector3(0, .3, .79), "•  •\n  ─")
		face.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		face.pixel_size = .007
		face.modulate = Color("80ebc0")
		vehicles.append(
			{
				"node": node,
				"label": info,
				"face": face,
				"home": p,
				"job": -1,
				"state": "IDLE",
				"path": PackedVector3Array(),
				"step": 0,
				"timer": 0.0,
				"cargo": null,
				"rotors": rotors
			}
		)


func meal(item: String, quantity: int) -> Node3D:
	var root := Node3D.new()
	var packaging := Node3D.new()
	packaging.name = "Packaging"
	root.add_child(packaging)
	var height := .16 + quantity * .18
	for x in [-.34, .34]:
		box(packaging, Vector3(x, height / 2, 0), Vector3(.025, height, .48), "bd915b")
	for z in [-.24, .24]:
		box(packaging, Vector3(0, height / 2, z), Vector3(.7, height, .025), "d8b47d")
	box(packaging, Vector3(0, height, 0), Vector3(.71, .025, .5), "d8b47d")
	box(packaging, Vector3(0, height + .015, 0), Vector3(.12, .015, .5), "3ba895")
	box(root, Vector3(0, .025, 0), Vector3(.65, .05, .44), "bd915b")
	for q in quantity:
		for index in 2:
			if (index == 0 and item == "Coffee") or (index == 1 and item == "Sandwich"):
				continue
			var food: Node3D = FOOD[index].instantiate()
			root.add_child(food)
			food.position = Vector3(-.13 + index * .29, .055 + q * .18, 0)
	return root


func receive(packet: Dictionary) -> void:
	if packet.get("type", "") == "error":
		if pending_run != "--none":
			pending_run = "--none"
			built_run = ""
			start_after_config = false
		storage_error = packet.message
		error_until = Time.get_ticks_msec() + 5000
		return
	if not packet.has("state"):
		return
	if packet.get("server_id", "") != server_id:
		sound_effects.initialized = false
		server_id = packet.get("server_id", "")
		last_revision = -1
	var revision: int = int(packet.get("revision", 0))
	if revision < last_revision:
		return
	last_revision = revision
	if packet.state.run_id == pending_run:
		return
	pending_run = "--none"
	state = packet.state
	config["auto_orders"] = state.config.get("auto_orders", true)
	ui.autonomy.set_pressed_no_signal(config["auto_orders"])
	config["sfx_enabled"] = state.config.get("sfx_enabled", true)
	config["sfx_volume"] = state.config.get("sfx_volume", .65)
	sound_effects.apply_config(config)
	ui.sync_sound()
	var next_locale: String = state.config.get("language", "en")
	if next_locale != locale:
		locale = next_locale
		config["language"] = locale
		TranslationServer.set_locale(locale)
		voices = DisplayServer.tts_get_voices_for_language(locale.replace("_", "-"))
		if voices.is_empty() and locale in ["ko", "ja", "cs", "en"]:
			voices = DisplayServer.tts_get_voices_for_language(locale)
		ui.refresh_language()
	if Time.get_ticks_msec() > error_until:
		storage_error = packet.get("error", "")
	running = state.running
	sim_time = state.time
	if state.run_id != built_run and not state.run_id.is_empty():
		config = state.config
		build_world()
		built_run = state.run_id
		receipts.clear()
		ui.sync_config()
		if start_after_config:
			start_after_config = false
			send({"command": "start"})
	if not world:
		return
	if state.vehicles.size() != vehicles.size() or state.cafes.size() != cafes.size():
		return
	sound_effects.observe(state)
	orders.assign(state.orders)
	for i in vehicles.size():
		var v: Dictionary = vehicles[i]
		var data: Dictionary = state.vehicles[i]
		if v.state != data.state and i == focus_index and focus_kind == "drone":
			var phrases := {
				"LOADING": "Hello chef. Ready to collect the order.",
				"DELIVERING": "Items secured. On my way to the customer.",
				"UNLOADING": "Hello! Your order has arrived.",
				"RETURNING": "Delivery complete. Thank you. Returning to base."
			}
			if speech and not voices.is_empty() and phrases.has(data.state):
				DisplayServer.tts_speak(tr(phrases[data.state]), voices[0], 75, 1.0, 1.0, 0, true)
		if v.state != data.state:
			v["display_timer"] = float(data.timer)
		v.state = data.state
		v.job = int(data.job)
		v.timer = data.timer
		v["payload"] = data.payload
		v["maintenance"] = data.get("maintenance", {})
		v["target_position"] = vec(data.position)
		v["target_rotation"] = data.rotation
		v["target_pitch"] = data.get("body", {}).get("pitch", 0.0)
		v["target_roll"] = data.get("body", {}).get("roll", 0.0)
		if not v.has("pose_buffer"):
			v["pose_buffer"] = preload("res://scripts/drone_pose_buffer.gd").new()
		var attitude := (
			Basis
			. from_euler(Vector3(v.target_pitch, v.target_rotation, v.target_roll))
			. get_rotation_quaternion()
		)
		v.pose_buffer.push(
			float(state.time) / presentation_time_scale,
			Time.get_ticks_usec() / 1000000.0,
			v.target_position,
			attitude
		)
		v.label.text = (
			tr("DRONE %02d / %s\nBAT %.0f%% / %.2f kg")
			% [i + 1, tr(v.state), data.battery, data.payload]
		)
		v.face.text = "^  ^\n  ∪" if v.state in ["LOADING", "UNLOADING"] else "•  •\n  ─"
	for i in cafes.size():
		if cafes[i].job >= 0 and int(state.cafes[i].job) < 0:
			cafes[i].owner.celebrate = 1.8
		cafes[i].job = int(state.cafes[i].job)
		cafes[i].timer = state.cafes[i].timer
	# Select one current order per customer; historical deliveries never spawn food.
	var latest := {}
	for job in orders:
		latest[int(job.human)] = job
	for id in latest:
		var job: Dictionary = latest[id]
		var human: Dictionary = humans[id]
		if human.active_order != int(job.id):
			human.active_order = int(job.id)
		if job.get("apartment", false):
			if not is_instance_valid(human.apartment):
				human.apartment = apartment(human.base, id)
			human.node.position = human.base + Vector3(0, 8.15, 7.0)
		else:
			human.node.position = human.base
		human.node.stay_near = job.get("apartment", false)
		human.bin.position = human.node.position + Vector3(1.25, 0, 0)
		human.node.receiving = false
		if int(job.drone) >= 0 and job.state != "DELIVERED":
			var drone: Dictionary = vehicles[int(job.drone)]
			human.node.receiving = drone.state == "UNLOADING"
			var direction: Vector3 = drone.node.position - human.node.position
			if direction.length() < 25.0 or human.node.receiving:
				human.node.stay_near = true
				human.node.facing = atan2(-direction.x, -direction.z)
		human.label.text = tr("%s / %s\n%s") % [customer_name(id), tr(job.state), tr(job.item)]


func update_visuals(delta: float) -> void:
	for i in docks.size():
		var dock: Dictionary = docks[i]
		var drone: Dictionary = vehicles[i]
		var phase: String = drone.state
		dock.cable.visible = phase == "CHARGING"
		dock.arm.rotation.z = sin(sim_time * 2) * .3 if phase == "REPAIRING" else 0.0
		dock.label.text = (
			tr("SERVICE DOCK %02d / %s")
			% [
				i + 1,
				tr(phase) if phase in ["CHARGING", "DIAGNOSING", "REPAIRING"] else tr("READY")
			]
		)
	for cafe in cafes:
		cafe.owner.working = cafe.job >= 0
		if running:
			cafe.owner.animate_character(delta, 0.0)
		cafe.sign.text = shop_name(cafes.find(cafe)) + tr(" / ROBOT KITCHEN")
		if cafe.job < 0:
			cafe.lift.position.y = 1.68
			cafe.food.visible = false
			cafe.label.text = tr("READY FOR ORDERS")
			continue
		var job: Dictionary = orders[cafe.job]
		if cafe.food_job != job.id:
			cafe.food.queue_free()
			cafe.food = meal(job.item, int(job.quantity))
			cafe.node.add_child(cafe.food)
			cafe.food_job = job.id
		cafe.food.position = Vector3(0, 1.68, .3)
		cafe.lift.position.y = 1.68
		cafe.food.visible = true
		cafe.food.get_node("Packaging").visible = job.state != "COOKING"
		if job.state == "COOKING":
			cafe.food.visible = cafe.timer > 3
			cafe.label.text = (
				tr("ROBOT COOKING / %d%%") % int(cafe.timer / (12 + job.quantity * 4) * 100)
			)
			for i in cafe.arms.size():
				cafe.arms[i].rotation.x = sin(sim_time * 3 + i * PI) * .14 - 1.35
		elif job.state == "PACKING":
			cafe.label.text = tr("ROBOT PACKING / ORDER #%02d") % job.id
			for i in cafe.arms.size():
				cafe.arms[i].rotation.x = -1.4 + sin(sim_time * 2 + i * PI) * .12
		elif job.state == "SHIPPING":
			cafe.label.text = tr("ROBOT SHIPPING / DISPATCH CONVEYOR")
			cafe.food.position.z = lerpf(.3, 5.5, clampf(cafe.timer / 4, 0, 1))
		elif job.state == "READY":
			cafe.food.position.z = 5.5
			cafe.label.text = tr("ORDER #%02d / READY FOR DRONE") % job.id
		else:
			cafe.food.visible = false
			cafe.label.text = tr("ROBOT SHIPPING / LIFT HANDOFF")
			if job.drone >= 0:
				cafe.lift.position.y = lerpf(1.68, 3.0, clampf(vehicles[job.drone].timer / 3, 0, 1))
			for arm in cafe.arms:
				arm.rotation.x = -1.4
	for v in vehicles:
		v["display_timer"] = lerpf(
			float(v.get("display_timer", v.timer)), float(v.timer), 1.0 - exp(-16.0 * delta)
		)
		if v.has("pose_buffer"):
			v.node.transform = v.pose_buffer.sample(Time.get_ticks_usec() / 1000000.0)
		v.node.visible = not (
			first_person and focus_kind == "drone" and vehicles.find(v) == focus_index
		)
		if running and v.state not in ["IDLE", "CHARGING", "DIAGNOSING", "REPAIRING"]:
			for rotor in v.rotors:
				rotor.rotation.y += delta * 35
		var loaded: bool = (
			v.state in ["LOADING", "DELIVERING", "UNLOADING"]
			or (v.state == "RECOVERY RETURN" and v.get("payload", 0.0) > 0.0)
		)
		if loaded and v.job >= 0:
			var job: Dictionary = orders[v.job]
			if not is_instance_valid(v.cargo):
				v.cargo = meal(job.item, int(job.quantity))
				world.add_child(v.cargo)
				v["cargo_order"] = job.id
			var p: Vector3 = v.node.position - Vector3.UP * .8
			if v.state == "LOADING":
				p = (cafes[job.cafe].node.position + Vector3(0, 1.68, 5.5)).lerp(
					p, smoothstep(0.0, 1.0, clampf(v.display_timer / 3, 0, 1))
				)
			if v.state == "UNLOADING":
				p = p.lerp(
					customer_hands(humans[job.human]),
					smoothstep(0.0, 1.0, clampf(v.display_timer / 3, 0, 1))
				)
			v.cargo.position = p
		elif is_instance_valid(v.cargo):
			var delivered := false
			for job in orders:
				if job.id == v.get("cargo_order", -1) and job.state == "DELIVERED":
					var human: Dictionary = humans[job.human]
					if human.active_order == int(job.id):
						if is_instance_valid(human.held):
							human.held.queue_free()
						human.held = v.cargo
						human.meal_kind = job.item
						human.node.drinking = job.item == "Coffee"
						human.trash_clock = -1.0
						human.node.disposing = false
						human.hold_until = sim_time + 12.0
						human.meal_clock = 0.0
						human.node.celebrate = 3.5
						receipts[job.id] = true
						delivered = true
					break
			if not delivered:
				v.cargo.queue_free()
			v.cargo = null
	for human in humans:
		human.node.disposal_offset = human.node.to_local(human.bin.global_position) * .48
		if running:
			human.node.animate_character(delta, 0.0)
		human.node.holding = is_instance_valid(human.held)
		if human.node.holding:
			human.held.position = customer_hands(human)
			human.held.rotation.y = human.node.rotation.y + human.node.body.rotation.y
			human.held.rotation.x = (
				human.node.consume_blend * (-.35 if human.node.drinking else -.1)
			)
			if running:
				human.meal_clock += delta
			if human.meal_clock > 3.5 and human.meal_clock <= 12.0:
				var drink: bool = (
					human.meal_kind == "Coffee"
					or (human.meal_kind == "Sandwich + Coffee" and human.meal_clock > 8.0)
				)
				var food_key := "coffee" if drink else "sandwich"
				if human.held.get_meta("consuming", "") != food_key:
					human.held.queue_free()
					human.held = (
						(
							preload("res://assets/coffee.glb")
							if drink
							else preload("res://assets/sandwich.glb")
						)
						. instantiate()
					)
					world.add_child(human.held)
					human.held.set_meta("consuming", food_key)
					human.held.position = customer_hands(human)
					human.node.drinking = drink
			if human.meal_clock > 12.0 and human.trash_clock < 0.0:
				human.held.queue_free()
				human.held = (
					(
						preload("res://assets/empty-coffee-cup.glb")
						if human.node.drinking
						else preload("res://assets/meal-wrapper.glb")
					)
					. instantiate()
				)
				world.add_child(human.held)
				human.trash_clock = 0.0
				human.node.disposing = true
			if human.trash_clock >= 0.0:
				if running:
					human.trash_clock += delta
				var toss := clampf((human.trash_clock - 2.0) / .8, 0, 1)
				var bin_top: Vector3 = human.bin.to_global(Vector3(0, 1.02, 0))
				human.held.global_position = (
					customer_hands(human).lerp(bin_top, toss) + Vector3.UP * sin(toss * PI) * .4
				)
				if toss >= 1.0:
					human.held.queue_free()
					human.held = null
					human.node.disposing = false
					human.trash_clock = -1.0


func customer_hands(human: Dictionary) -> Vector3:
	return human.node.body.to_global(
		Vector3(0, 1.05, -.34).lerp(
			Vector3(0, 1.24 if human.node.drinking else 1.34, -.30), human.node.consume_blend
		)
	)


func _process(delta: float) -> void:
	advance_orbit_return(delta)
	if "--motion-diagnostics" in OS.get_cmdline_user_args() and not motion_reported:
		motion_seconds += delta
		motion_frames += 1
		motion_stalls += int(delta > .05)
		if motion_seconds > 20:
			motion_reported = true
			print(
				"MOTION_TIMING fps=",
				motion_frames / motion_seconds,
				" frames_over_50ms=",
				motion_stalls
			)
			for vehicle in vehicles:
				if vehicle.has("pose_buffer"):
					print(
						"MOTION_BUFFER frames=",
						vehicle.pose_buffer.frames,
						" underruns=",
						vehicle.pose_buffer.underruns
					)
	var raw: String = transport.poll_json()
	if not raw.is_empty():
		var packet = JSON.parse_string(raw)
		if packet is Array:
			for message in packet:
				receive(message)
	if not transport.connected():
		retry += delta
		if retry > 2:
			retry = 0
			if backend_pid < 0 and OS.get_environment("COAST_WS").is_empty():
				var executable := ProjectSettings.globalize_path(
					"res://../rust/target/debug/coast-backend"
				)
				if FileAccess.file_exists(executable):
					backend_pid = OS.create_process(executable, [])
			transport.connect_backend(backend_url)
		return
	if world:
		if director and running and not ui.menu_open:
			director_timer += delta
			if director_timer >= 8.0:
				director_timer = 0.0
				var active: Array[int] = []
				for i in vehicles.size():
					if vehicles[i].state not in ["IDLE", "CHARGING", "DIAGNOSING", "REPAIRING"]:
						active.append(i)
				if not active.is_empty():
					focus_kind = "drone"
					focus_index = active[director_cursor % active.size()]
					director_cursor += 1
					first_person = false
					orbit += .65
					zoom = 10
					elevation = .25
		update_visuals(delta)
		if opening_rig.active:
			if not ui.story.visible and not ui.menu_open:
				opening_rig.advance(self, delta)
			return
		if random_camera:
			if not ui.menu_open:
				random_rig.advance(self, delta)
			return
		if free_camera:
			update_free_camera(delta)
			return
		var list: Array = (
			park.wildlife.targets
			if focus_kind == "nature"
			else (
				docks
				if focus_kind == "dock"
				else (
					cafes
					if focus_kind == "cafe"
					else (vehicles if focus_kind == "drone" else humans)
				)
			)
		)
		if not list.is_empty():
			focus_index = posmod(focus_index, list.size())
			var node: Node3D = list[focus_index].node
			var p: Vector3 = (
				node.position
				+ (
					Vector3.UP
					* (
						4.0
						if focus_kind == "nature" and focus_index == 0
						else .65 if focus_kind == "nature" else 1.5
					)
				)
			)
			if first_person and focus_kind == "drone":
				follow_subject = 0
				var forward: Vector3 = node.basis.z
				camera.global_position = node.position + forward * .65 + Vector3.UP * .15
				camera.look_at(camera.global_position + forward * 30 - Vector3.UP * 2)
			else:
				var desired := (
					p
					+ (
						Vector3(
							sin(orbit) * cos(elevation), sin(elevation), cos(orbit) * cos(elevation)
						)
						* zoom
					)
				)
				if focus_kind == "drone":
					var subject: int = node.get_instance_id()
					if follow_subject != subject:
						follow_rig.reset(p, camera.global_position - p)
						follow_subject = subject
					camera.global_position = follow_rig.advance(p, desired - p, delta, true)
					if camera.global_position.distance_squared_to(follow_rig.anchor) > .01:
						camera.look_at(follow_rig.anchor, Vector3.UP)
					return
				follow_subject = 0
				var next_camera: Vector3 = camera.global_position.lerp(
					desired, 1.0 - exp(-5.0 * delta)
				)
				if focus_kind == "nature":
					next_camera.y = maxf(
						next_camera.y, park.ground_height(next_camera.x, next_camera.z) + .4
					)
					var ray := PhysicsRayQueryParameters3D.create(p, next_camera)
					var hit := get_world_3d().direct_space_state.intersect_ray(ray)
					if not hit.is_empty() and focus_index > 0:
						next_camera = hit.position + hit.normal * .25
				camera.global_position = next_camera
				camera.look_at(p)


func start_random_camera() -> void:
	set_free_camera(false)
	director = false
	first_person = false
	random_camera = true
	random_rig.reset()
	ui.set_menu_visible(false)


func set_free_camera(enabled: bool) -> void:
	opening_rig.active = false
	random_camera = false
	free_camera = enabled
	follow_subject = 0
	free_velocity = Vector3.ZERO
	if enabled:
		director = false
		first_person = false


func update_free_camera(delta: float) -> void:
	if ui.menu_open or get_viewport().gui_get_focus_owner() != null or not get_window().has_focus():
		free_velocity = Vector3.ZERO
		return
	var direction := Vector3.ZERO
	if (
		not ui.menu_open
		and get_viewport().gui_get_focus_owner() == null
		and get_window().has_focus()
	):
		direction.x = (
			float(Input.is_physical_key_pressed(KEY_D))
			- float(Input.is_physical_key_pressed(KEY_A))
		)
		direction.z = (
			float(Input.is_physical_key_pressed(KEY_S))
			- float(Input.is_physical_key_pressed(KEY_W))
		)
		direction.y = (
			float(Input.is_physical_key_pressed(KEY_E))
			- float(Input.is_physical_key_pressed(KEY_Q))
		)
	var desired := (
		camera.global_basis * Vector3(direction.x, 0, direction.z) + Vector3.UP * direction.y
	)
	var speed := free_speed * (3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	free_velocity = free_velocity.lerp(desired.normalized() * speed, 1.0 - exp(-8.0 * delta))
	camera.global_position += free_velocity * delta


func begin_orbit_drag() -> void:
	if orbit_dragging:
		return
	if not orbit_returning:
		orbit_home = Vector2(orbit, elevation)
	orbit_dragging = true
	orbit_returning = false
	director = false


func _input(event: InputEvent) -> void:
	# Releases must be seen even when the pointer ends over a HUD control.
	if event is InputEventMouseButton and not event.pressed and orbit_dragging:
		if (event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)) == 0:
			orbit_dragging = false
			orbit_returning = true
			orbit_release = Vector2(orbit, elevation)
			orbit_return_time = 0.0


func advance_orbit_return(delta: float) -> void:
	if focus_kind != "drone" or first_person or free_camera or random_camera:
		orbit_dragging = false
		orbit_returning = false
		return
	if not orbit_returning or ui.menu_open:
		return
	orbit_return_time += maxf(delta, 0.0)
	var t := clampf(orbit_return_time / ORBIT_RETURN_SECONDS, 0.0, 1.0)
	var weight := (
		0.0
		if t <= 0.0
		else (
			1.0
			if t >= 1.0
			else (
				pow(2.0, 20.0 * t - 10.0) * .5
				if t < .5
				else (2.0 - pow(2.0, -20.0 * t + 10.0)) * .5
			)
		)
	)
	orbit = lerp_angle(orbit_release.x, orbit_home.x, weight)
	elevation = lerpf(orbit_release.y, orbit_home.y, weight)
	if t >= 1.0:
		orbit = orbit_home.x
		elevation = orbit_home.y
		orbit_returning = false


func _unhandled_input(input: InputEvent) -> void:
	if ui.title_visible:
		if (
			input is InputEventKey
			and input.pressed
			and not input.echo
			and input.physical_keycode == KEY_SPACE
		):
			ui.story.open()
		return
	if input is InputEventKey and input.pressed and not input.echo:
		if input.physical_keycode == KEY_F:
			set_free_camera(not free_camera)
		if input.physical_keycode == KEY_ESCAPE:
			ui.set_menu_visible(false)
		if input.physical_keycode == KEY_V:
			first_person = not first_person
		if input.physical_keycode == KEY_M:
			ui.toggle_menu()
	if input is InputEventMouse and ui.menu_open:
		return
	var following_drone := (
		focus_kind == "drone" and not first_person and not free_camera and not random_camera
	)
	if (
		input is InputEventMouseMotion
		and (
			(input.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0
			or (following_drone and (input.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0)
		)
	):
		if free_camera:
			camera.rotation.y -= input.relative.x * .003
			camera.rotation.x = clampf(camera.rotation.x - input.relative.y * .003, -1.5, 1.5)
			return
		director_timer = -15.0
		if following_drone:
			begin_orbit_drag()
		orbit -= input.relative.x * .008
		elevation = clampf(
			elevation + input.relative.y * .006, -.3 if focus_kind == "nature" else .08, 1.4
		)
	if input is InputEventMouseButton and input.pressed:
		if following_drone and input.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			begin_orbit_drag()
		if free_camera:
			if input.button_index == MOUSE_BUTTON_WHEEL_UP:
				free_speed = minf(150, free_speed * 1.2)
			if input.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				free_speed = maxf(2, free_speed / 1.2)
			return
		if input.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(4, zoom - 2)
		if input.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(140, zoom + 2)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		ui.save_display_preferences()
		send({"command": "stop"})
		await get_tree().create_timer(.2).timeout
		get_tree().quit()


func apartment(p: Vector3, index: int) -> Node3D:
	var node := Node3D.new()
	world.add_child(node)
	node.position = p
	var light := OmniLight3D.new()
	node.add_child(light)
	light.position = Vector3(0, 10.5, 0)
	light.omni_range = 10
	light.light_energy = 1.8
	light.light_color = Color("ffe8c4")
	var house = preload("res://assets/balcony-house.glb").instantiate()
	node.add_child(house)
	label(node, Vector3(0, 13.5, 5), tr("APARTMENT %02d / BALCONY DELIVERY") % (index + 1))
	return node


func test_fleet() -> void:
	await preload("res://scripts/fleet_test.gd").new().run(self)


func gallery() -> void:
	await preload("res://scripts/fleet_gallery.gd").new().run(self)


func start_simulation() -> void:
	if not transport.connected():
		storage_error = "Wait for the backend connection"
		return
	if state.get("vehicles", []).is_empty():
		start_after_config = true
		configure(
			int(ui.drone_count.value),
			int(ui.cafe_count.value),
			int(ui.human_count.value),
			ui.mode.get_item_metadata(ui.mode.selected),
			ui.autonomy.button_pressed
		)
	else:
		send({"command": "start"})


func autonomous_start() -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while not transport.connected() or state.is_empty():
		if Time.get_ticks_msec() > deadline:
			storage_error = "Autonomous start: backend unavailable"
			return
		await get_tree().process_frame
	ui.show_menu()
	ui.autonomy.set_pressed_no_signal(true)
	if "--massive" in OS.get_cmdline_user_args():
		start_after_config = true
		configure(8, 3, 20, "Massive", true)
	else:
		if not state.get("vehicles", []).is_empty():
			send({"command": "autonomy", "enabled": true})
		start_simulation()
	ui.set_menu_visible(false)
	while not running and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if running:
		print(
			"AUTONOMOUS_STARTED: automatic customer orders, chef preparation, drone delivery and return"
		)
