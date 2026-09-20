extends RefCounted


func until(sim: Node, test: Callable, seconds := 80.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if test.call():
			return true
		await sim.get_tree().process_frame
	push_error("Gallery timeout")
	sim.get_tree().quit(1)
	return false


func capture(sim: Node, name: String) -> void:
	await sim.get_tree().create_timer(.6).timeout
	await RenderingServer.frame_post_draw
	sim.get_viewport().get_texture().get_image().save_png("res://fleet-" + name + ".png")


func run(sim: Node) -> void:
	await until(sim, func(): return sim.transport.connected())
	sim.speech = false
	await capture(sim, "title")
	if "--operations-only" in OS.get_cmdline_user_args():
		var original_size: Vector2i = sim.get_window().size
		sim.ui.title_layout_button.pressed.emit()
		await capture(sim, "title-vertical")
		assert(sim.get_window().size.x < sim.get_window().size.y)
		sim.ui.fullscreen_button.pressed.emit()
		await capture(sim, "title-fullscreen")
		assert(sim.get_window().mode == Window.MODE_FULLSCREEN)
		var saved_display: Dictionary = sim.ui.DISPLAY_PREFS.read_latest()
		assert(
			saved_display.window_mode == "fullscreen" and saved_display.orientation == "vertical"
		)
		sim.ui.fullscreen_button.pressed.emit()
		await sim.get_tree().create_timer(.4).timeout
		assert(sim.get_window().mode == Window.MODE_WINDOWED)
		assert(sim.get_window().size == Vector2i(650, 900))
		assert(sim.ui.DISPLAY_PREFS.read_latest().window_mode == "windowed")
		sim.ui.title_layout_button.pressed.emit()
		sim.get_window().size = original_size

	if "--story-only" in OS.get_cmdline_user_args():
		sim.ui.toggle_layout()
		await capture(sim, "title-vertical")
		sim.ui.toggle_layout()
		sim.ui.story.open()
		for chapter_index in 5:
			sim.ui.story.page = chapter_index
			sim.ui.story.show_page()
			await sim.get_tree().create_timer(2.0).timeout
			await capture(sim, "story-shot-" + str(chapter_index + 1))
		sim.ui.story.page = 3
		sim.ui.story.show_page()
		await sim.get_tree().create_timer(2.0).timeout
		await capture(sim, "story-horizontal")
		sim.ui.toggle_layout()
		await sim.get_tree().create_timer(1.0).timeout
		await capture(sim, "story-vertical")
		sim.ui.story.play_title_reveal()
		await sim.get_tree().create_timer(4.4).timeout
		sim.ui.story.cinematic_tween.pause()
		await capture(sim, "title-reveal-vertical")
		assert(sim.ui.story.cinematic_title.get_line_count() == 2)
		assert(sim.ui.story.cinematic_text.size.x <= sim.ui.story.size.x)
		sim.ui.toggle_layout()
		await capture(sim, "title-reveal-horizontal")
		assert(sim.ui.story.cinematic_title.get_line_count() == 2)
		sim.ui.story.cinematic_tween.play()
		await until(sim, func(): return not sim.ui.story.visible)
		await capture(sim, "opening-wide")
		await capture(sim, "opening-tree")
		await capture(sim, "opening-rabbit")
		await capture(sim, "opening-sky")
		await until(sim, func(): return not sim.opening_rig.active)
		await capture(sim, "opening-drone")
		print("FLEET_GALLERY_OK")
		sim.get_tree().quit()
		return
	sim.ui.show_menu()
	sim.configure(1, 1, 1, "Solo", false)
	await until(sim, func(): return sim.state.get("vehicles", []).size() == 1)
	if "--operations-only" in OS.get_cmdline_user_args():
		sim.send({"command": "language", "language": "ko"})
		await until(sim, func(): return sim.locale == "ko")
		sim.ui.set_menu_visible(false)
		sim.ui.open_page(3)
		await capture(sim, "game-menu")
		sim.ui.set_menu_visible(false)
		await capture(sim, "game-play")
		sim.ui.details_open = true
		sim.ui.inspector_page.select(0)
		await capture(sim, "operations-right")
		sim.ui.toggle_layout()
		await capture(sim, "operations-bottom")
		sim.ui.open_page(3)
		await capture(sim, "game-menu-vertical")
		sim.ui.toggle_layout()
		sim.ui.set_menu_visible(false)
		sim.ui.details_open = false
		sim.place_order("Sandwich + Coffee", 1, 0, 0, false)
		sim.send({"command": "start"})
		await until(sim, func(): return sim.receipts.size() == 1)
		sim.focus_kind = "human"
		sim.focus_index = 0
		sim.zoom = 5
		sim.orbit = PI + .25
		sim.elevation = .12
		await capture(sim, "meal-joy")
		await until(sim, func(): return sim.humans[0].meal_clock > 5)
		await capture(sim, "meal-eating")
		await until(sim, func(): return sim.humans[0].meal_clock > 9)
		await capture(sim, "meal-drinking")
		await until(sim, func(): return sim.humans[0].trash_clock > 1.9)
		await capture(sim, "meal-bin")
		await until(sim, func(): return not is_instance_valid(sim.humans[0].held))

		print("FLEET_GALLERY_OK")
		sim.get_tree().quit()
		return
	if "--nature-only" in OS.get_cmdline_user_args():
		sim.ui.set_menu_visible(false)
		sim.focus_kind = "nature"
		sim.first_person = false
		sim.orbit = .1
		sim.elevation = .18
		for shot in [
			{"index": 0, "zoom": 30.0, "name": "lone-tree"},
			{"index": 1, "zoom": 3.5, "name": "cat"},
			{"index": 4, "zoom": 3.5, "name": "rabbit"}
		]:
			sim.focus_index = shot.index
			sim.zoom = shot.zoom
			sim.elevation = -.075 if shot.index == 0 else .18
			await sim.get_tree().create_timer(1.0).timeout
			await capture(sim, shot.name)
		var dressing: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/park-dressing.json")
		)
		var garden_target := Node3D.new()
		sim.park.wildlife.add_child(garden_target)
		garden_target.position = sim.vec(dressing.placements[3].position) + Vector3(0, -2, 0)
		var lone_target: Dictionary = sim.park.wildlife.targets[0]
		sim.park.wildlife.targets[0] = {"node": garden_target}
		sim.focus_index = 0
		sim.zoom = 10
		sim.elevation = .1
		sim.orbit = .65
		await sim.get_tree().create_timer(1.0).timeout
		await capture(sim, "garden")
		var cast_base: Vector3 = sim.vec(dressing.placements[3].position) + Vector3(4, 0, 4)
		cast_base.y = sim.park.ground_height(cast_base.x, cast_base.z)
		var preview_cast: Array[Node3D] = []
		for index in 3:
			var actor := CharacterBody3D.new()
			actor.set_script(preload("res://scripts/walker.gd"))
			actor.variant = index
			sim.world.add_child(actor)
			actor.position = cast_base + Vector3((index - 1) * 1.35, 0, 0)
			actor.position.y = sim.park.ground_height(actor.position.x, actor.position.z)
			actor.rotation.y = PI
			actor.set_physics_process(false)
			actor.phase = .9 + index
			actor.receiving = index == 2
			for frame in 60:
				actor.animate_character(1.0 / 60, 1.25 if index == 1 else 0.0)
			preview_cast.append(actor)
		garden_target.position = cast_base + Vector3(0, -2, 0)
		sim.zoom = 6
		sim.orbit = .2
		sim.elevation = .05
		await sim.get_tree().create_timer(.7).timeout
		await capture(sim, "cast-animation")
		for actor in preview_cast:
			actor.queue_free()
		sim.park.wildlife.targets[0] = lone_target
		var lake: Dictionary = sim.park.data.water[0]
		var biggest_area := 0.0
		for candidate in sim.park.data.water:
			var area := 0.0
			var ring: Array = candidate.rings[0]
			for i in ring.size():
				var a: Array = ring[i]
				var b: Array = ring[(i + 1) % ring.size()]
				area += a[0] * b[1] - b[0] * a[1]
			if absf(area) > biggest_area:
				biggest_area = absf(area)
				lake = candidate
		var lake_center := Vector3.ZERO
		for p in lake.rings[0]:
			lake_center += Vector3(p[0], float(lake.level), p[1])
		lake_center /= lake.rings[0].size()
		var lake_target := Node3D.new()
		sim.park.wildlife.add_child(lake_target)
		lake_target.position = lake_center
		var tree_target: Dictionary = sim.park.wildlife.targets[0]
		sim.park.wildlife.targets[0] = {"node": lake_target}
		sim.focus_index = 0
		sim.zoom = 220
		sim.elevation = .6
		await sim.get_tree().create_timer(1.0).timeout
		await capture(sim, "lake")
		lake_target.position = (
			sim.vec(sim.park.landmark("WORLD PEACE GATE").position) + Vector3.UP * 8
		)
		sim.zoom = 86
		sim.elevation = .16
		sim.orbit = float(sim.park.landmark("WORLD PEACE GATE").angle) + .2
		await sim.get_tree().create_timer(1.0).timeout
		await capture(sim, "peace-gate")
		sim.ui.open_page(1)
		await capture(sim, "orders-ui")
		sim.ui.toggle_layout()
		await sim.get_tree().create_timer(.8).timeout
		await capture(sim, "portrait-ui")
		sim.ui.toggle_layout()
		sim.ui.set_menu_visible(false)
		sim.park.wildlife.targets[0] = tree_target
		var a: Vector3 = sim.park.wildlife.animals[0].node.position
		var query := PhysicsRayQueryParameters3D.create(a + Vector3.UP * 2, a - Vector3.UP * 2)
		var ground_hit: Dictionary = sim.get_world_3d().direct_space_state.intersect_ray(query)
		if not ground_hit.is_empty():
			print("NATURE_GROUND: ", ground_hit.collider.get_parent().name, " at ", a)
		print("FLEET_GALLERY_OK")
		sim.get_tree().quit()
		return

	sim.focus_kind = "dock"
	sim.focus_index = 0
	sim.zoom = 9
	sim.ui.set_menu_visible(false)
	sim.send({"command": "fault", "drone": 0})
	sim.send({"command": "start"})
	await until(
		sim,
		func():
			return (
				sim.vehicles[0].state == "REPAIRING"
				and sim.state.vehicles[0].maintenance.elapsed > 24
			)
	)
	sim.send({"command": "stop"})
	await until(sim, func(): return not sim.running)
	sim.focus_kind = "dock"
	sim.focus_index = 0
	sim.zoom = 9
	sim.ui.set_menu_visible(false)
	await capture(sim, "repair-dock")
	sim.send({"command": "start"})
	await until(sim, func(): return sim.vehicles[0].state == "IDLE")
	sim.send({"command": "stop"})
	await until(sim, func(): return not sim.running)
	sim.place_order("Sandwich + Coffee", 1, 0, 0, true)
	await until(sim, func(): return sim.orders.size() == 1)
	sim.send({"command": "start"})
	await until(sim, func(): return sim.orders[0].state == "COOKING" and sim.cafes[0].timer >= 6)
	sim.send({"command": "stop"})
	await until(sim, func(): return not sim.running)
	sim.focus_kind = "cafe"
	sim.focus_index = 0
	sim.zoom = 15
	sim.elevation = .24
	sim.ui.set_menu_visible(false)
	await capture(sim, "cafe")
	for code in preload("res://scripts/localization.gd").CODES:
		sim.send({"command": "language", "language": code})
		await until(sim, func(): return sim.locale == code)
		sim.ui.set_menu_visible(true)
		await capture(sim, "language-" + code)
	sim.send({"command": "language", "language": "en"})
	await until(sim, func(): return sim.locale == "en")
	sim.ui.set_menu_visible(false)
	for page in range(4):
		sim.ui.inspector_page.select(page)
		await capture(sim, "dashboard-%d" % page)
	sim.ui.inspector_page.select(0)
	sim.send({"command": "start"})
	await until(sim, func(): return sim.orders[0].state == "SHIPPING" and sim.cafes[0].timer >= 1.5)
	sim.send({"command": "stop"})
	await until(sim, func(): return not sim.running)
	await capture(sim, "shipping")
	sim.send({"command": "start"})
	await until(sim, func(): return sim.vehicles[0].state == "LOADING")
	sim.send({"command": "stop"})
	await until(sim, func(): return not sim.running)
	sim.focus_kind = "drone"
	sim.zoom = 7
	sim.elevation = .16
	sim.orbit = 3.6
	await capture(sim, "pickup")
	sim.send({"command": "start"})
	await until(
		sim, func(): return sim.vehicles[0].state == "UNLOADING" and sim.vehicles[0].timer > 1.4
	)
	sim.send({"command": "stop"})
	await until(sim, func(): return not sim.running)
	sim.focus_kind = "human"
	sim.zoom = 13
	sim.elevation = .16
	sim.orbit = .1
	await capture(sim, "apartment")
	sim.orbit = 1.1
	sim.zoom = 9
	await capture(sim, "balcony-handoff")
	sim.send({"command": "start"})
	await until(sim, func(): return sim.orders[0].state == "DELIVERED")
	await sim.get_tree().create_timer(.15).timeout
	sim.send({"command": "stop"})
	await until(sim, func(): return not sim.running)
	sim.zoom = 7
	await capture(sim, "happy-customer")
	sim.send({"command": "language", "language": "ko"})
	await until(sim, func(): return sim.locale == "ko")
	sim.focus_kind = "drone"
	sim.focus_index = 0
	sim.zoom = 12
	await capture(sim, "selected-drone-horizontal")
	sim.ui.toggle_layout()
	await capture(sim, "selected-drone-vertical")
	sim.ui.toggle_layout()
	sim.send({"command": "language", "language": "ko"})
	await until(sim, func(): return sim.locale == "ko")
	sim.ui.dashboard.open()
	await capture(sim, "operations-dashboard")
	sim.ui.toggle_layout()
	await capture(sim, "operations-dashboard-portrait")
	sim.ui.toggle_layout()
	sim.ui.dashboard.close()
	sim.focus_kind = "drone"
	sim.first_person = true
	await capture(sim, "cockpit")
	sim.focus_kind = "nature"
	sim.focus_index = 0
	sim.first_person = false
	sim.zoom = 22
	sim.elevation = .18
	await capture(sim, "lone-tree")
	sim.focus_index = 1
	sim.zoom = 3.5
	await capture(sim, "cat")
	sim.focus_index = 4
	await capture(sim, "rabbit")
	sim.start_random_camera()
	sim.random_rig.rng.seed = 25
	sim.random_rig.advance(sim, .016)
	for frame in 120:
		sim.random_rig.advance(sim, sim.random_rig.duration / 240.0)
	await capture(sim, "random-flight")
	for frame in 120:
		sim.random_rig.advance(sim, sim.random_rig.duration / 240.0)
	await capture(sim, "random-arrival")
	print("FLEET_GALLERY_OK")
	sim.get_tree().quit()
