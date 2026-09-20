extends RefCounted
var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func until(sim: Node, condition: Callable, seconds := 30.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		for vehicle in sim.state.get("vehicles", []):
			if not sim.park.in_flight_area(sim.vec(vehicle.position)):
				check(false, "Active drone must stay within Olympic Park")
				return false
		if condition.call():
			return true
		await sim.get_tree().process_frame
	return false


func run(sim: Node) -> void:
	var tree := sim.get_tree()
	var preferences = preload("res://scripts/frontend_preferences.gd")
	var preferences_dir: String = preferences.data_directory().path_join("display-recovery-test")
	var display_record := {
		"schema": 1,
		"window_mode": "fullscreen",
		"orientation": "vertical",
		"window_size": [650, 900]
	}
	check(
		preferences.append(display_record, preferences_dir) == OK,
		"Frontend display preferences save as JSONL"
	)
	var restored: Dictionary = preferences.read_latest(preferences_dir)
	check(
		(
			restored.window_mode == "fullscreen"
			and restored.orientation == "vertical"
			and restored.window_size == [650, 900]
		),
		"Display mode and window geometry survive disk reload"
	)
	var damaged := FileAccess.open(
		preferences_dir.path_join("frontend.jsonl"), FileAccess.READ_WRITE
	)
	damaged.seek_end()
	damaged.store_string('{"schema":')
	damaged.close()
	check(
		preferences.read_latest(preferences_dir) == restored,
		"Interrupted JSONL tail preserves last complete display record"
	)
	display_record.window_mode = "windowed"
	check(
		preferences.append(display_record, preferences_dir) == OK,
		"Next display save recovers after an interrupted tail"
	)
	check(
		preferences.read_latest(preferences_dir).window_mode == "windowed",
		"Latest valid record wins"
	)
	display_record.window_size = [-1, 0]
	check(
		preferences.append(display_record, preferences_dir) == ERR_INVALID_DATA,
		"Invalid display dimensions cannot replace preferences"
	)
	var ui_model = preload("res://scripts/fleet_ui.gd")
	var vertical: Rect2 = ui_model.operations_rect(Vector2(650, 900), 180.0)
	var horizontal: Rect2 = ui_model.operations_rect(Vector2(1280, 800), 180.0)
	check(
		vertical.position.x == 24 and vertical.position.y > 450 and vertical.end.y == 830,
		"Vertical operations docks across the bottom above footer"
	)
	check(
		horizontal.position.x > 640 and horizontal.end.x == 1255,
		"Horizontal operations docks on the right"
	)
	var dashboard_model = preload("res://scripts/dashboard.gd")
	var report: Dictionary = dashboard_model.aggregate(
		{
			"time": 100.0,
			"orders":
			[
				{"state": "DELIVERED", "created": 80.0, "delivered": 95.0},
				{"state": "DELIVERED", "created": 20.0, "delivered": 50.0},
				{"state": "ORDERED"},
				{"state": "FAILED"}
			],
			"vehicles":
			[{"state": "DELIVERING", "battery": 20.0}, {"state": "CHARGING", "battery": 80.0}]
		}
	)
	check(
		report.delivered == 2 and report.pending == 1,
		"Dashboard excludes failures from pending orders"
	)
	check(
		report.mean == 22.5 and report.battery == 50.0,
		"Dashboard computes fulfillment and battery averages"
	)
	check(
		report.bins[10] == 1 and report.bins[1] == 1, "Dashboard bins deliveries by simulation time"
	)
	check(
		report.working == 1 and report.alerts == 1,
		"Dashboard distinguishes charging from active flight"
	)
	check(dashboard_model.aggregate({}).mean == 0.0, "Empty dashboard has no division by zero")
	var cinematic = preload("res://scripts/random_camera.gd")
	check(
		cinematic.ease_in_out(0.0) == 0.0 and cinematic.ease_in_out(1.0) == 1.0,
		"Cinematic easing has exact endpoints"
	)
	check(absf(cinematic.ease_in_out(.5) - .5) < .0001, "Cinematic easing is symmetric")
	var ui_font = preload("res://assets/fonts/game-ui.tres")
	for glyph in "한글廣東話中文日本語Čeština":
		check(ui_font.has_char(glyph.unicode_at(0)), "Bundled font includes " + glyph)
	var playback := preload("res://scripts/drone_pose_buffer.gd").new()
	var last_position := Vector3.ZERO
	var last_time := -1.0
	for frame in 241:
		var now := frame / 120.0
		if frame % 6 == 0:
			playback.push(now, now, Vector3(now * 12.0, 20, 0), Quaternion.IDENTITY)
		var pose: Transform3D = playback.sample(now)
		if now > .2 and last_time > .15:
			check(
				absf((pose.origin.x - last_position.x) / (now - last_time) - 12.0) < .01,
				"20 Hz telemetry renders constant cruise speed at 120 FPS"
			)
		last_position = pose.origin
		last_time = now
	var jittered := preload("res://scripts/drone_pose_buffer.gd").new()
	var next_packet := 0
	for frame in 241:
		var now := frame / 120.0
		while next_packet <= 40:
			var sent := next_packet * .05
			var arrival := sent + (.025 if next_packet % 2 == 1 else 0.0)
			if arrival > now:
				break
			jittered.push(sent, arrival, Vector3(sent * 12, 20, 0), Quaternion.IDENTITY)
			next_packet += 1
		if now > .2:
			check(
				absf(jittered.sample(now).origin.x - (now - .15) * 12) < .001,
				"Network arrival jitter does not shake the airframe"
			)
	var drifting := preload("res://scripts/drone_pose_buffer.gd").new()
	var previous_x := 0.0
	var previous_speed := 12.0
	var steady_underruns := 0
	for frame in 3601:
		var now := frame / 120.0
		if frame % 6 == 0:
			# Sender runs 3% slower: a fixed startup offset exhausts 100 ms in ~3 seconds.
			var sender := now * .97
			drifting.push(sender, now, Vector3(sender * 12, 20, 0), Quaternion.IDENTITY)
		var x := drifting.sample(now).origin.x
		if now > 5.0:
			var speed := (x - previous_x) * 120
			check(
				speed > 11.0 and speed < 12.1, "Clock drift must not produce hold-and-jump playback"
			)
			check(absf(speed - previous_speed) < .08, "Clock correction changes speed smoothly")
			previous_speed = speed
			if drifting.playback_time > float(drifting.samples[-1].time):
				steady_underruns += 1
		else:
			previous_speed = (x - previous_x) * 120
		previous_x = x
	check(steady_underruns == 0, "Sustained sender slowdown keeps snapshots buffered")
	var recovered := preload("res://scripts/drone_pose_buffer.gd").new()
	recovered.push(0, 0, Vector3.ZERO, Quaternion.IDENTITY)
	recovered.sample(.1)
	recovered.push(1, 1, Vector3(12, 0, 0), Quaternion(Vector3.UP, 1.0))
	check(
		recovered.sample(1).origin.length() < .001,
		"Stream recovery starts from the displayed pose without snapping"
	)
	check(
		absf(recovered.sample(1.15).origin.x - 6.0) < .001,
		"Large stream correction blends smoothly"
	)
	check(
		absf(recovered.sample(1.31).origin.x - 12.0) < .001,
		"Recovery blend converges to the current snapshot"
	)
	var parked: Transform3D = playback.sample(5.0)
	check(
		parked.origin.distance_to(Vector3(24, 20, 0)) < .001,
		"Network interruption holds the last pose without drift"
	)
	var turning := preload("res://scripts/drone_pose_buffer.gd").new()
	turning.push(0, 0, Vector3.ZERO, Quaternion(Vector3.UP, deg_to_rad(179)))
	turning.push(.05, .05, Vector3.ZERO, Quaternion(Vector3.UP, deg_to_rad(-179)))
	var midpoint: Transform3D = turning.sample(.175)
	check(
		(midpoint.basis * Vector3.FORWARD).dot(Vector3.BACK) > .999,
		"Heading wrap interpolates through two degrees, not a full spin"
	)
	var rig := preload("res://scripts/follow_camera_rig.gd").new()
	var orbit_offset := Vector3(0, 4, 12)
	rig.reset(Vector3.ZERO, orbit_offset)
	var max_motion := 0.0
	var previous := rig.anchor
	for frame in 240:
		var target := Vector3(.2 if frame % 2 == 0 else -.2, .1 if frame % 2 == 0 else -.1, 0)
		var camera_position: Vector3 = rig.advance(target, orbit_offset, 1.0 / 60.0)
		max_motion = maxf(max_motion, rig.anchor.distance_to(previous))
		previous = rig.anchor
		check(
			(camera_position - rig.anchor).distance_to(orbit_offset) < .0001,
			"No camera angle oscillation from noisy telemetry"
		)
	check(max_motion < .025, "Follow camera attenuates rapid position tremor")
	var synchronized := preload("res://scripts/follow_camera_rig.gd").new()
	synchronized.reset(Vector3.ZERO, orbit_offset)
	for frame in 240:
		var displayed_drone := Vector3(frame * .1, sin(frame * .1) * .2, cos(frame * .1))
		var camera_position: Vector3 = synchronized.advance(
			displayed_drone, orbit_offset, 1.0 / 60, true
		)
		check(
			(camera_position - displayed_drone).distance_to(orbit_offset) < .00001,
			"Follow camera and airframe share the exact presentation pose without double lag"
		)
	var slow := preload("res://scripts/follow_camera_rig.gd").new()
	var fast := preload("res://scripts/follow_camera_rig.gd").new()
	slow.reset(Vector3.ZERO, orbit_offset)
	fast.reset(Vector3.ZERO, orbit_offset)
	for frame in 30:
		slow.advance(Vector3(10, 2, 4), orbit_offset, 1.0 / 30)
	for frame in 120:
		fast.advance(Vector3(10, 2, 4), orbit_offset, 1.0 / 120)
	check(
		slow.anchor.distance_to(fast.anchor) < .0001,
		"Follow damping is consistent at 30 and 120 FPS"
	)
	await tree.physics_frame
	await tree.physics_frame
	var gate: Node3D = sim.park.get_node("WorldPeaceGate")
	var space: PhysicsDirectSpaceState3D = sim.get_world_3d().direct_space_state
	var passage := PhysicsRayQueryParameters3D.create(
		gate.to_global(Vector3(0, 5, -24)), gate.to_global(Vector3(0, 5, 24))
	)
	check(space.intersect_ray(passage).is_empty(), "Peace gate central passage stays open")
	var roof_ray := PhysicsRayQueryParameters3D.create(
		gate.to_global(Vector3(0, 30, 0)), gate.to_global(Vector3(0, 15, 0))
	)
	var roof_hit: Dictionary = space.intersect_ray(roof_ray)
	check(not roof_hit.is_empty(), "Blender gate roof has flight collision")
	if not roof_hit.is_empty():
		check(
			absf(gate.to_local(roof_hit.position).y - 20.5) < .3,
			"Gate roof collision matches model"
		)
	for path in ["res://assets/alex.glb", "res://assets/mei.glb", "res://assets/chef_bo.glb"]:
		var cast_member: Node3D = load(path).instantiate()
		sim.add_child(cast_member)
		for pivot in ["Leg_L", "Leg_R", "Arm_L", "Arm_R", "Knee_L", "Knee_R", "HeadPivot"]:
			check(
				cast_member.find_child(pivot, true, false) != null, "Cast walking pivot: " + pivot
			)
		for joint in [
			{"name": "HeadPivot", "height": 1.34},
			{"name": "Knee_L", "height": .44},
			{"name": "Knee_R", "height": .44}
		]:
			var node: Node3D = cast_member.find_child(joint.name, true, false)
			var local: Vector3 = (
				cast_member.global_transform.affine_inverse() * node.global_position
			)
			check(
				absf(local.y - joint.height) < .01,
				"Exported joint keeps its anatomical height: " + joint.name
			)
		cast_member.free()
	var walker := CharacterBody3D.new()
	walker.set_script(preload("res://scripts/walker.gd"))
	sim.add_child(walker)
	walker.set_physics_process(false)
	walker.phase = PI / 2
	for i in 60:
		walker.animate_character(1.0 / 60, 1.25)
	check(absf(walker.knees[0].rotation.x) > .1, "Walking bends the knee")
	walker.receiving = true
	for i in 120:
		walker.animate_character(1.0 / 60, 0)
	check(walker.limbs[2].rotation.x < -.8, "Receiving reaches forward at chest height")
	check(absf(walker.limbs[0].rotation.x) < .001, "Stopping settles the walking pose")
	walker.queue_free()
	var wildlife: Node3D = sim.park.wildlife
	var model: Node3D = preload("res://assets/cb-robot.glb").instantiate()
	sim.add_child(model)
	var low := INF
	var high := -INF
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var bounds: AABB = mesh.mesh.get_aabb()
		for corner in 8:
			var point: Vector3 = (
				model.global_transform.affine_inverse()
				* mesh.global_transform
				* bounds.get_endpoint(corner)
			)
			low = minf(low, point.y)
			high = maxf(high, point.y)
	check(absf(high - low - 1.8) < .01, "CB robot is 1.80 m after Blender export")
	check(model.find_child("CB_Chest_Badge", true, false) != null, "CB logo is present")
	check(
		(
			model.find_child("Shoulder_L", true, false) != null
			and model.find_child("Shoulder_R", true, false) != null
		),
		"Robot has two animation pivots"
	)
	model.queue_free()
	var meadow = wildlife.get_node("MeadowDetail")
	check(meadow.multimesh.instance_count > 1000, "Lawn detail was actually populated")
	check(meadow.ground_samples.size() > 10, "Lawn has CPU placement samples")
	for tuft in meadow.ground_samples:
		check(
			absf(tuft.y - sim.park.ground_height(tuft.x, tuft.z) - .012) < .015,
			"Lawn tufts follow terrain"
		)
	check(wildlife.animals.size() == 9, "Three cats and six rabbits exist")
	check(
		(
			wildlife.lone_tree.position.distance_to(
				sim.park.vec(sim.park.landmark("LONE TREE").position)
			)
			< 1
		),
		"Lone tree uses mapped coordinates"
	)
	var original: Vector3 = wildlife.animals[0].node.position
	for step in 100:
		wildlife.advance(.1)
	check(original.distance_to(wildlife.animals[0].node.position) > .1, "Animals wander")
	for animal in wildlife.animals:
		check(wildlife.safe_ground(animal.node.position), "Animals remain on clear ground")
		check(
			(
				absf(
					(
						animal.node.position.y
						- sim.park.ground_height(animal.node.position.x, animal.node.position.z)
					)
				)
				< .01
			),
			"Animals follow terrain"
		)

	check(
		await until(sim, func(): return sim.transport.connected()), "Rust FFI WebSocket connection"
	)
	var robot: Node3D = preload("res://assets/cb-robot.glb").instantiate()
	sim.add_child(robot)
	for shoulder_name in ["Shoulder_L", "Shoulder_R"]:
		var shoulder: Node3D = robot.find_child(shoulder_name, true, false)
		check(
			absf(shoulder.position.y - 1.445) < .001, "Robot shoulder pivot has anatomical height"
		)
		var actuators := shoulder.find_children("*actuator*", "MeshInstance3D", true, false)
		check(not actuators.is_empty(), "Robot actuator exists under shoulder pivot")
		if not actuators.is_empty():
			var socket: Vector3 = shoulder.global_position
			for angle in [0.0, -.55, -1.4]:
				shoulder.rotation.x = angle
				check(
					actuators[0].global_position.distance_to(socket) < .001,
					"Animated robot actuator remains attached to its shoulder"
				)
	robot.queue_free()
	var story: Control = sim.ui.story
	story.open()
	check(story.visible and sim.ui.menu_open, "Story opens as a modal 3D scene")
	check(story.page == 0 and not story.revealed, "Story starts with the first chapter")
	story.advance()
	check(story.page == 0 and story.revealed, "First advance reveals the current dialogue")
	story.advance()
	check(story.page == 1, "Second advance moves to the next chapter")
	check(
		story.dialogue.text.contains("Subway") and story.dialogue.text.contains("Starbucks"),
		"Story includes the requested lunch"
	)
	for i in 3:
		story.advance()
		story.advance()
	check(
		story.page == 4 and sim.ui.title_visible,
		"Story reaches the final chapter without starting simulation early"
	)
	story.close()
	check(
		(
			not story.visible
			and story.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
		),
		"Closing story releases its rendering work"
	)
	sim.ui.drone_count.value = 2
	sim.ui.cafe_count.value = 2
	sim.ui.human_count.value = 4
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	sim._unhandled_input(key)
	check(
		story.visible and story.page == 0 and sim.ui.title_visible, "Title Space begins the story"
	)
	for chapter_index in 5:
		story.advance_autoplay(20.0)
	check(
		story.visible and story.busy and story.cinematic.visible,
		"Story ends with cinematic title reveal"
	)
	check(
		await until(sim, func(): return not story.visible),
		"Cinematic title completes without key presses"
	)
	check(
		await until(sim, func(): return not sim.ui.title_visible and sim.running),
		"Autoplay finishes by starting the automatic field trial"
	)
	check(sim.opening_rig.active, "Story starts the park opening before exposing the world")
	for second in 4:
		sim.opening_rig.advance(sim, 1.0)
		check(sim.opening_rig.active, "Opening remains active until its fifth second")
		check(
			(
				sim.camera.global_position.y
				>= sim.top(sim.camera.global_position.x, sim.camera.global_position.z) + 1.0
			),
			"Opening clears terrain and building roofs"
		)
	sim.opening_rig.advance(sim, 1.0)
	check(
		not sim.opening_rig.active and sim.focus_kind == "drone",
		"Opening hands off to drone follow"
	)
	check(sim.camera.global_position.is_finite(), "Opening camera remains finite")
	sim.ui.mode.select(0)
	sim.ui.drone_count.get_line_edit().text = "2"
	sim.ui.cafe_count.get_line_edit().text = "2"
	sim.ui.human_count.get_line_edit().text = "4"
	await sim.ui.apply_counts()
	check(
		await until(sim, func(): return sim.running), "Applying counts resumes a running simulation"
	)
	check(
		(
			sim.state.config.drones == 2
			and sim.state.config.cafes == 2
			and sim.state.config.humans == 4
		),
		"Typed counts override the Solo preset and reach the backend"
	)
	check(
		sim.vehicles.size() == 2 and sim.cafes.size() == 2 and sim.humans.size() == 4,
		"Applied counts rebuild client models"
	)
	var old_zoom: float = sim.zoom
	var old_elevation: float = sim.elevation
	var old_orbit: float = sim.orbit
	sim.ui.focus_nature(true)
	check(
		str(sim.park.wildlife.targets[sim.focus_index].node.name).begins_with("Rabbit"),
		"Rabbit menu chooses a rabbit"
	)
	sim.ui.focus_nature(false)
	check(
		sim.focus_index == 0 and sim.focus_kind == "nature", "Lone tree menu chooses the landmark"
	)
	sim.focus_kind = "drone"
	sim.zoom = old_zoom
	sim.elevation = old_elevation
	sim.orbit = old_orbit
	sim.send({"command": "autonomy", "enabled": false})
	await tree.create_timer(.5).timeout
	check(not sim.ui.title_panel.visible, "Title fade finishes and hides overlay")
	sim.ui.set_menu_visible(true)
	await tree.create_timer(.4).timeout
	sim.ui.set_menu_visible(false)
	await tree.create_timer(.10).timeout
	check(sim.ui.menu.visible and sim.ui.menu.modulate.a < 1.0, "Menu fades before hiding")
	sim.ui.set_menu_visible(true)
	sim.ui.set_menu_visible(false)
	sim.ui.set_menu_visible(true)
	await tree.create_timer(.4).timeout
	check(
		sim.ui.menu.visible and is_equal_approx(sim.ui.menu.modulate.a, 1.0),
		"Latest toggle cancels stale fade completion"
	)
	sim.ui.open_page(1)
	check(sim.ui.pages.current_tab == 1 and sim.ui.menu_open, "Orders opens directly")
	sim.ui.set_menu_visible(false)
	var orbit_before: float = sim.orbit
	var elevation_before: float = sim.elevation
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag.relative = Vector2(80, 20)
	sim.focus_kind = "drone"
	sim.first_person = false
	sim.free_camera = false
	sim.random_camera = false
	sim.director = true
	sim._unhandled_input(drag)
	check(
		sim.orbit < orbit_before and sim.elevation > elevation_before and not sim.director,
		"Left drag orbits the followed drone and keeps manual control"
	)
	var dragged_orbit: float = sim.orbit
	sim.ui.menu_open = true
	sim._unhandled_input(drag)
	check(sim.orbit == dragged_orbit, "Menu interaction does not orbit the drone")
	sim.ui.menu_open = false
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	sim._input(release)
	check(
		sim.orbit_returning and sim.orbit == dragged_orbit,
		"Releasing begins return without snapping"
	)
	sim.advance_orbit_return(sim.ORBIT_RETURN_SECONDS * .5)
	check(
		is_equal_approx(sim.orbit, lerp_angle(dragged_orbit, orbit_before, .5)),
		"Exponential return reaches halfway at half duration"
	)
	sim.advance_orbit_return(sim.ORBIT_RETURN_SECONDS * .5)
	check(
		(
			not sim.orbit_returning
			and is_equal_approx(sim.orbit, orbit_before)
			and is_equal_approx(sim.elevation, elevation_before)
		),
		"Exponential return restores the original view"
	)
	var fly_key := InputEventKey.new()
	fly_key.physical_keycode = KEY_F
	fly_key.pressed = true
	sim._unhandled_input(fly_key)
	check(sim.free_camera and not sim.director, "F enters independent free camera")
	var free_position: Vector3 = sim.camera.global_position
	await tree.create_timer(.2).timeout
	check(
		sim.camera.global_position.distance_to(free_position) < .01,
		"Free camera stops following drone"
	)
	sim.ui.set_menu_visible(true)
	sim.free_velocity = Vector3(10, 0, 0)
	sim.update_free_camera(.1)
	check(sim.free_velocity == Vector3.ZERO, "Menu blocks free-camera movement")
	sim.set_free_camera(false)
	sim.ui.inspector_page.select(2)
	await tree.create_timer(.45).timeout
	check(
		sim.ui.displayed_page == 2 and is_equal_approx(sim.ui.orders_label.modulate.a, 1.0),
		"Inspector fades out and back in"
	)
	sim.ui.inspector_page.select(0)
	var initial_portrait: bool = sim.get_window().size.x < sim.get_window().size.y
	sim.ui.toggle_layout()
	await tree.create_timer(.25).timeout
	check(
		(sim.get_window().size.x < sim.get_window().size.y) != initial_portrait,
		"Layout button toggles orientation"
	)
	check(
		(
			sim.ui.layout_button.text
			== (sim.tr("Vertical") if not initial_portrait else sim.tr("Horizontal"))
		),
		"Toggle displays current orientation"
	)
	sim.ui.toggle_layout()
	await tree.create_timer(.25).timeout
	check(
		(sim.get_window().size.x < sim.get_window().size.y) == initial_portrait,
		"Second toggle restores orientation"
	)
	sim.speech = false
	sim.ui.drone_count.value = 2
	sim.ui.cafe_count.value = 2
	sim.ui.human_count.value = 4
	sim.ui.autonomy.set_pressed_no_signal(false)
	# A fresh manual scenario isolates order assertions from initial autonomous demand.
	# Drain the initial run before resetting; SQLite deliberately keeps its order history.
	check(
		await until(
			sim,
			func():
				return (
					sim.orders.all(func(j): return j.state == "DELIVERED")
					and sim.vehicles.all(func(v): return v.state == "IDLE")
				),
			45
		),
		"Initial autonomous demand finishes before reset"
	)
	sim.send({"command": "stop"})
	await until(sim, func(): return not sim.running)
	var previous_run: String = sim.state.run_id
	sim.configure(2, 2, 4, "Massive", false)
	check(
		await until(sim, func(): return sim.state.run_id != previous_run and sim.orders.is_empty()),
		"Fresh manual scenario has no automatic orders"
	)
	sim.start_simulation()
	check(
		await until(sim, func(): return sim.state.get("vehicles", []).size() == 2),
		"Config counts must roundtrip through Rust"
	)
	check(
		await until(sim, func(): return sim.running),
		"Start must configure and run a fresh simulator"
	)
	sim.send({"command": "stop"})
	await until(sim, func(): return not sim.running)
	var stale: Dictionary = sim.state.duplicate(true)
	stale.run_id = ""
	stale.vehicles = []
	sim.receive(
		{
			"type": "state",
			"state": stale,
			"server_id": sim.server_id,
			"revision": sim.last_revision - 1
		}
	)
	check(sim.state.vehicles.size() == 2, "Delayed snapshots must not replace newer fleet state")
	sim.send({"command": "sound", "enabled": false, "volume": 0.25})
	check(
		await until(sim, func(): return not sim.config.get("sfx_enabled", true)),
		"Sound mute roundtrip"
	)
	check(
		AudioServer.is_bus_mute(AudioServer.get_bus_index("SimulatorEffects")), "Effects bus muted"
	)
	var count_before: int = sim.sound_effects.effects_played
	sim.sound_effects.play_effect("order", Vector3.ZERO, true)
	check(sim.sound_effects.effects_played == count_before, "Muted effects do not play")
	sim.send({"command": "sound", "enabled": true, "volume": 0.65})
	check(
		await until(sim, func(): return sim.config.get("sfx_enabled", false)),
		"Sound settings restored"
	)
	check(sim.sound_effects.samples.size() == 6, "All six sound samples load")
	sim.send({"command": "instant_charge", "drone": 0})
	check(
		await until(sim, func(): return sim.running and sim.state.vehicles[0].battery > 99.9),
		"Instant charge resumes simulation via WebSocket"
	)
	sim.send({"command": "stop"})
	await until(sim, func(): return not sim.running)
	sim.ui.dashboard.open()
	check(
		sim.ui.dashboard.visible and sim.ui.menu_open, "Dashboard opens and blocks camera controls"
	)
	check(
		sim.ui.dashboard.fleet_rows.size() == sim.vehicles.size(), "Dashboard displays every drone"
	)
	sim.ui.dashboard.fleet_rows[0].button.pressed.emit()
	check(
		not sim.ui.dashboard.visible and sim.focus_kind == "drone" and sim.focus_index == 0,
		"Dashboard drone opens follow camera"
	)
	sim.ui.drone_list.select(1)
	sim.selected_hud.refresh()
	check(sim.selected_hud.selected_index == 1, "Status panel follows selected dropdown drone")
	check(
		absf(sim.selected_hud.battery.value - sim.state.vehicles[1].battery) < .01,
		"Status battery matches selected snapshot"
	)
	sim.ui.drone_list.select(0)
	sim.selected_hud.refresh()
	check(sim.selected_hud.selected_index == 0, "Status updates when selection changes")
	var camera_before: Transform3D = sim.camera.global_transform
	sim.start_random_camera()
	sim.random_rig.rng.seed = 42
	sim.random_rig.advance(sim, .016)
	check(
		sim.camera.global_position.distance_to(camera_before.origin) < .01,
		"Random camera begins at current position without a cut"
	)
	for frame in 240:
		sim.random_rig.advance(sim, 1.0 / 60.0)
		check(sim.camera.global_transform.is_finite(), "Random camera stays finite")
		check(
			(
				sim.camera.global_position.y
				>= sim.park.ground_height(
					sim.camera.global_position.x, sim.camera.global_position.z
				)
			),
			"Random camera clears terrain"
		)
	sim.set_free_camera(false)
	check(not sim.random_camera, "Manual view exits random camera")
	sim.camera.global_transform = camera_before
	var actor: Node = sim.humans[0].node
	actor.animate_character(.2, 0.0)
	var idle_pose: Vector3 = actor.body.position
	actor.animate_character(.4, 0.0)
	check(actor.body.position.distance_to(idle_pose) > .001, "Waiting NPC shifts weight")
	actor.celebrate = 3.5
	actor.animate_character(.1, 0.0)
	check(actor.body.position.y > .01, "Receipt celebration adds a happy bounce")
	actor.celebrate = 0.0
	var run_before: String = sim.state.run_id
	for code in preload("res://scripts/localization.gd").CODES:
		sim.send({"command": "language", "language": code})
		check(await until(sim, func(): return sim.locale == code), "Language switch " + code)
		check(
			sim.state.run_id == run_before and sim.vehicles.size() == 2,
			"Language preserves scenario"
		)
		check(
			sim.ui.item.get_item_metadata(0) == "Sandwich", "Translated menu retains protocol item"
		)
		if code != "en":
			check(sim.tr("START") != "START", "Translation exists " + code)
		for page in range(4):
			sim.ui.inspector_page.select(page)
			sim.ui._process(0.0)
	sim.ui.inspector_page.select(0)
	sim.send({"command": "language", "language": "en"})
	await until(sim, func(): return sim.locale == "en")
	sim.place_order("Sandwich + Coffee", 2, 0, 0, true)
	sim.place_order("Coffee", 1, 1, 1, false)
	check(await until(sim, func(): return sim.orders.size() == 2), "Menu orders must reach backend")
	sim.send({"command": "start"})
	check(await until(sim, func(): return sim.running), "Start simulation")
	check(
		await until(
			sim, func(): return sim.orders.any(func(j): return j.state == "OUT FOR DELIVERY")
		),
		"Chef must cook and hand food to drone"
	)
	check(
		sim.humans.all(func(h): return not is_instance_valid(h.held)),
		"Customers remain empty-handed before arrival"
	)
	sim.send({"command": "stop"})
	check(await until(sim, func(): return not sim.running), "Stop simulation")
	var stopped_time: float = sim.sim_time
	await tree.create_timer(.3).timeout
	check(sim.sim_time == stopped_time, "Stopped simulation must freeze its clock")
	check(sim.game_effects.fleet.size() == sim.vehicles.size(), "GPU effect sets match fleet")
	for fx in sim.game_effects.fleet:
		for kind in ["wash", "dust", "charge", "sparks", "burst"]:
			check(fx[kind] is GPUParticles3D, "Native GPU particle emitter")
			check(fx[kind].speed_scale == 0.0, "Particles freeze with simulation")
	for sound in sim.sound_effects.loops.values():
		check(not sound.playing, "Paused simulation stops motor and kitchen loops")
	check(sim.sound_effects.effects_played > 0, "Order and workflow effects triggered")
	sim.focus_kind = "drone"
	sim.focus_index = 0
	sim.first_person = true
	await tree.create_timer(.15).timeout
	check(not sim.vehicles[0].node.visible, "First-person camera hides own airframe")
	check(sim.camera.global_position.is_finite(), "First-person camera transform")
	var vehicle: Node3D = sim.vehicles[0].node
	var camera_mount: Vector3 = vehicle.position + vehicle.basis.z * .65 + Vector3.UP * .15
	check(
		sim.camera.global_position.distance_to(camera_mount) < .1,
		"First-person camera must follow the selected aircraft mount"
	)
	sim.first_person = false
	await tree.create_timer(.15).timeout
	check(sim.vehicles[0].node.visible, "Third-person camera restores airframe")
	sim.send({"command": "start"})
	check(
		await until(
			sim,
			func():
				return (
					sim.orders.all(func(j): return j.state == "DELIVERED")
					and sim.vehicles.all(func(v): return v.state == "IDLE")
				),
			45
		),
		"Apartment and outside deliveries must complete and drones return"
	)
	check(is_instance_valid(sim.humans[0].apartment), "Blender balcony residence must exist")
	check(sim.receipts.size() == 2, "Both customers must receive Blender food models")
	var receipt_count: int = sim.receipts.size()
	sim.receive(
		{
			"state": sim.state.duplicate(true),
			"server_id": sim.server_id,
			"revision": sim.last_revision
		}
	)
	check(sim.receipts.size() == receipt_count, "Replayed history must not duplicate handoffs")
	check(
		await until(
			sim, func(): return sim.humans.all(func(h): return not is_instance_valid(h.held)), 20.0
		),
		"Completed meals are consumed and litter reaches the bin"
	)
	sim.send({"command": "stop"})
	await until(sim, func(): return not sim.running)
	# A challenge enables demand over the FFI/WebSocket connection.
	check(int(sim.state.arcade.score) > 0, "Completed deliveries earn score")
	sim.send({"command": "challenge"})
	check(
		await until(sim, func(): return sim.state.config.auto_orders),
		"Challenge enables autonomous demand"
	)
	sim.start_simulation()
	check(
		await until(sim, func(): return sim.orders.size() > 2),
		"Customers must order without manual submission"
	)
	sim.ui.autonomy.button_pressed = false
	check(
		await until(sim, func(): return not sim.state.config.auto_orders),
		"Disable automatic demand"
	)
	check(
		await until(
			sim,
			func():
				return (
					sim.orders.all(func(j): return j.state == "DELIVERED")
					and sim.vehicles.all(func(v): return v.state == "IDLE")
				),
			45
		),
		"Existing autonomous orders must finish after demand is disabled"
	)
	sim.send({"command": "stop"})
	await until(sim, func(): return not sim.running)
	var paused_time: float = sim.sim_time
	await tree.create_timer(.2).timeout
	check(sim.sim_time == paused_time, "Pausing freezes mission time")
	check(sim.docks.size() == sim.vehicles.size(), "Dedicated maintenance docks exist")
	sim.send({"command": "fault", "drone": 0})
	await until(sim, func(): return sim.state.vehicles[0].maintenance.health == 55.0)
	sim.send({"command": "service", "drone": 1, "reason": "charge"})
	sim.send({"command": "start"})
	check(
		await until(sim, func(): return sim.vehicles[0].state == "REPAIRING"),
		"Fault enters diagnostics and repair"
	)
	sim.send({"command": "stop"})
	await until(sim, func(): return not sim.running)
	var repair_health: float = sim.state.vehicles[0].maintenance.health
	await tree.create_timer(.2).timeout
	check(
		sim.state.vehicles[0].maintenance.health == repair_health, "Repair pauses with simulation"
	)
	sim.send({"command": "start"})
	check(
		await until(
			sim,
			func():
				return (
					sim.state.vehicles[0].maintenance.repairs == 1
					and sim.vehicles.all(func(v): return v.state == "IDLE")
				),
			45
		),
		"Repair and charging return drones to service"
	)
	check(sim.state.vehicles[1].maintenance.charges >= 1, "Manual charging completes")
	sim.send({"command": "stop"})
	await until(sim, func(): return not sim.running)
	if failures.is_empty():
		print(
			"GODOT_FLEET_TEST_OK: title, config, menu orders, Rust FFI, WebSocket, cooking, payload, pause, cameras, apartment, delivery, return, autonomous demand"
		)
	tree.quit(0 if failures.is_empty() else 1)
