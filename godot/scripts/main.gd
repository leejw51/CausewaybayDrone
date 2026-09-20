extends Node3D

var drone: CharacterBody3D
var hud: Control
var park: Node3D
var game: Node


func _ready() -> void:
	configure_input()
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://assets/park_sky.gdshader")
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.sky_material = sky_mat
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("a1bed6")
	settings.ambient_light_energy = 0.27
	settings.tonemap_mode = Environment.TONE_MAPPER_ACES
	settings.ssao_enabled = true
	settings.ssao_radius = .8
	settings.ssao_intensity = .65
	settings.glow_enabled = true
	settings.glow_intensity = .35
	settings.glow_bloom = .04
	settings.tonemap_exposure = .92
	settings.fog_enabled = true
	settings.fog_light_color = Color("b6d8ed")
	settings.fog_density = .00011
	settings.fog_sky_affect = 0.0
	env.environment = settings
	add_child(env)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-32, -38, 0)
	sun.light_color = Color("fff0d5")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 320
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = .12
	sun.shadow_normal_bias = 2.0
	sun.light_angular_distance = 1.2
	park = Node3D.new()
	park.name = "Park"
	park.set_script(preload("res://scripts/real_map.gd"))
	add_child(park)
	drone = CharacterBody3D.new()
	drone.set_script(preload("res://scripts/drone.gd"))
	drone.spawn_position = Vector3(110, park.ground_height(110, -40) + 8, -40)
	drone.spawn_yaw = -1.05
	add_child(drone)
	game = Node.new()
	game.name = "MissionController"
	game.set_script(preload("res://scripts/mission_controller.gd"))
	game.drone = drone
	game.park = park
	game.active = not "--smoke" in OS.get_cmdline_user_args()
	drone.game = game
	add_child(game)
	var canvas := CanvasLayer.new()
	canvas.name = "CanvasLayer"
	add_child(canvas)
	hud = Control.new()
	hud.set_script(preload("res://scripts/hud.gd"))
	hud.drone = drone
	hud.park = park
	canvas.add_child(hud)
	var game_ui := Control.new()
	game_ui.name = "GameUI"
	game_ui.set_script(preload("res://scripts/game_ui.gd"))
	game_ui.game = game
	canvas.add_child(game_ui)
	var legacy := false
	for flag in [
		"--smoke", "--ai-test", "--order-test", "--ai-demo", "--water-view", "--buildings-view"
	]:
		if flag in OS.get_cmdline_user_args():
			legacy = true
	if not legacy:
		game.active = false
		game_ui.visible = false
		hud.visible = false
		drone.active = false
		drone.visual.visible = false
		drone.collision_layer = 0
		for walker in get_tree().get_nodes_in_group("park_walkers"):
			walker.queue_free()
		drone.set_process_unhandled_input(false)
		var fleet := preload("res://scripts/fleet_simulator.gd").new()
		fleet.park = park
		fleet.camera = drone.camera
		add_child(fleet)
		park.wildlife.sim = fleet
	if "--buildings-view" in OS.get_cmdline_user_args():
		drone.position = Vector3(735, 230, 680)
		drone.pitch = -.36
		drone.yaw = -.35
		drone.distance = 12
		drone.update_camera()
		hud.message = "Real-scale stadium district  /  R returns to Peace Gate"
	if "--smoke" in OS.get_cmdline_user_args():
		smoke_test.call_deferred()
		game_ui.visible = false
	if "--ai-test" in OS.get_cmdline_user_args():
		ai_test.call_deferred()
	if "--order-test" in OS.get_cmdline_user_args():
		order_test.call_deferred()
	if "--ai-demo" in OS.get_cmdline_user_args():
		await get_tree().physics_frame
		game.begin(true)
	if "--water-view" in OS.get_cmdline_user_args():
		drone.position = Vector3(890, 12, -340)
		drone.pitch = -.25
		drone.yaw = 0
		drone.distance = 8
		drone.update_camera()
		hud.message = "88 Lake  /  Transparent water, ripples and scene reflections"
	if "--capture" in OS.get_cmdline_user_args():
		capture.call_deferred()


func configure_input() -> void:
	var keys := {
		"forward": KEY_W,
		"back": KEY_S,
		"left": KEY_A,
		"right": KEY_D,
		"up": KEY_SPACE,
		"down": KEY_CTRL,
		"boost": KEY_SHIFT,
		"reset_drone": KEY_R,
		"release_mouse": KEY_ESCAPE,
		"interact": KEY_F,
		"start_mission": KEY_ENTER,
		"toggle_ai": KEY_TAB,
		"return_home": KEY_H
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = keys[action]
		InputMap.action_add_event(action, key)


func _unhandled_input(event: InputEvent) -> void:
	if game.active:
		if event.is_action_pressed("start_mission"):
			if game.phase == game.Phase.BRIEFING:
				get_node("CanvasLayer/GameUI").submit_order()
			else:
				game.begin(true)
		elif event.is_action_pressed("toggle_ai"):
			game.toggle_ai()
		elif event.is_action_pressed("return_home"):
			game.return_home()
		elif event.is_action_pressed("reset_drone"):
			game.restart()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact"):
		if drone.position.distance_to(park.delivery_point) < 7:
			hud.delivered = true
			hud.message = "Delivery complete  /  Coffee and sandwich received"
		elif drone.position.distance_to(park.rescue_point) < 10:
			hud.rescued = true
			hud.message = "Rescue support complete  /  Flotation delivered"
		else:
			hud.message = "Approach a station below 8 m, then press F"
	if event.is_action_pressed("reset_drone"):
		hud.message = "Aircraft returned to the launch pad"


func _process(_delta: float) -> void:
	if game and game.active:
		hud.message = game.status
		return
	if (
		Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and hud.message == "Click the view to take control"
	):
		hud.message = "Explore the park  /  Visit the cafe and lakeside rescue station"


func capture() -> void:
	await get_tree().create_timer(9 if "--ai-demo" in OS.get_cmdline_user_args() else 3).timeout
	await RenderingServer.frame_post_draw
	var output := (
		"res://buildings-preview.png"
		if "--buildings-view" in OS.get_cmdline_user_args()
		else "res://preview.png"
	)
	if "--water-view" in OS.get_cmdline_user_args():
		output = "res://water-preview.png"
	if "--ai-demo" in OS.get_cmdline_user_args():
		output = "res://ai-flight-preview.png"
	get_viewport().get_texture().get_image().save_png(output)
	if "--water-view" in OS.get_cmdline_user_args():
		await get_tree().create_timer(1).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://water-motion-preview.png")
	for probe in get_tree().get_nodes_in_group("water_reflection_probes"):
		probe.queue_free()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("CAPTURE_OK")
	get_tree().quit()


func smoke_test() -> void:
	await preload("res://scripts/real_map_test.gd").new().run(self)


func ai_test() -> void:
	await preload("res://scripts/ai_game_test.gd").new().run(self)


func order_test() -> void:
	await preload("res://scripts/order_test.gd").new().run(self)
