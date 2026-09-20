extends Control

const CHAPTERS = [
	[
		"RUST CODER",
		"Welcome to Rust Con, everyone! Seoul Olympic Park is ours for the day. Let's build something amazing!"
	],
	[
		"RUST CODER",
		"Lunch is on me! Subway sandwiches and Starbucks iced coffee for everyone... Wait. How am I going to carry all of this?"
	],
	[
		"GOOD SKYNET",
		"Need a hand, Rust Coder? I'm here to help! You bring the ideas. My robot chefs and drones will bring the lunch."
	],
	[
		"PARTICIPANT",
		"Whoa! My lunch flew here?! Thanks, little drone! This is already my favorite Rust Con."
	],
	[
		"RUST CODER",
		"Ready, Skynet? Let's make everyone smile. Our first delivery adventure starts NOW!"
	]
]
var sim: Node
var page := 0
var busy := false
var viewport: SubViewport
var view: SubViewportContainer
var camera: Camera3D
var actors: Array[Node3D] = []
var robot_arms: Array[Node] = []
var blades: Array[Node] = []
var parcel: Node3D
var heading: Label
var subtitle: Label
var chapter: Label
var dialogue: Label
var card: PanelContainer
var copy: VBoxContainer
var next: Button
var orientation: Button
var progress: Label
var cinematic_art: TextureRect
var cinematic_sparks: CPUParticles2D
var art_tween: Tween
var cinematic: ColorRect
var cinematic_text: VBoxContainer
var cinematic_title: Label
var cinematic_tween: Tween
var controls: HBoxContainer
var autoplay_bar: ProgressBar
var fade: Tween
var clock := 0.0
var page_clock := 0.0
var focus := Vector3(0, 1.15, -1)
var revealed := false
var previous_menu := false


func label(parent: Node, value: String, pixels: int) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size", pixels)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func actor(path: String, position: Vector3, scale_factor := 1.0) -> Node3D:
	var node: Node3D = load(path).instantiate()
	viewport.add_child(node)
	node.position = position
	node.scale *= scale_factor
	return node


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 60
	var back := ColorRect.new()
	back.color = Color("102c3f")
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	view = SubViewportContainer.new()
	view.stretch = true
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	view.add_child(viewport)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = preload("res://assets/textures/story-sky-codex.png")
	sky.sky_material = panorama
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("cce8ff")
	env.ambient_light_energy = .45
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = .9
	env.glow_enabled = true
	environment.environment = env
	viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -28, 0)
	sun.light_color = Color("ffe2af")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	viewport.add_child(sun)
	actor("res://assets/story-stage.glb", Vector3(0, -.06, 0))
	actor("res://assets/world-peace-gate.glb", Vector3(0, 0, -5.5), .12)
	actor("res://assets/lone-tree.glb", Vector3(-6, 0, -4), .28)
	actor("res://assets/lone-tree.glb", Vector3(6, 0, -5), .28)
	actors.append(actor("res://assets/rust-coder.glb", Vector3(-1.2, 0, 0), 1.25))
	actors.append(actor("res://assets/cb-robot.glb", Vector3(1.3, 0, .2), 1.15))
	actors.append(actor("res://assets/coast_drone.glb", Vector3(0, 3, -.4), .24))
	actors.append(actor("res://assets/alex.glb", Vector3(-3.5, 0, -1.2)))
	actors.append(actor("res://assets/mei.glb", Vector3(3.3, 0, -1.4)))
	for part in ["Shoulder_L", "Shoulder_R"]:
		var arm = actors[1].find_child(part, true, false)
		if arm:
			robot_arms.append(arm)
	blades = actors[2].find_children("Propeller*", "MeshInstance3D", true, false)
	parcel = Node3D.new()
	viewport.add_child(parcel)
	for item in ["sandwich", "coffee"]:
		var food: Node3D = load("res://assets/" + item + ".glb").instantiate()
		parcel.add_child(food)
		food.position.x = -.22 if item == "sandwich" else .22
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 48
	viewport.add_child(camera)
	camera.position = Vector3(5, 4, 12)
	camera.look_at(Vector3(0, 1.2, 0))
	var particles := GPUParticles3D.new()
	particles.amount = 36
	particles.lifetime = 4
	particles.position.y = 2
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(6, 2, 4)
	process.gravity = Vector3(0, .15, 0)
	process.scale_min = .02
	process.scale_max = .05
	process.color = Color("ffdd87")
	particles.process_material = process
	var spark := SphereMesh.new()
	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.albedo_color = Color("ffdd87")
	spark.material = spark_material
	particles.draw_pass_1 = spark
	viewport.add_child(particles)
	heading = label(self, "CAUSEWAYBAY DRONE", 26)
	heading.add_theme_font_override("font", preload("res://assets/fonts/retro-title.tres"))
	heading.modulate = Color("fff1cc")
	heading.add_theme_color_override("font_outline_color", Color("15394c"))
	heading.add_theme_constant_override("outline_size", 6)
	subtitle = label(self, "RUST CON / OLYMPIC PARK", 20)
	subtitle.modulate = Color("15394c")
	controls = HBoxContainer.new()
	controls.position = Vector2(24, 96)
	add_child(controls)
	orientation = sim.ui.button(controls, "Horizontal", func(): sim.ui.toggle_layout())
	sim.ui.button(controls, "Back", close)
	card = PanelContainer.new()
	add_child(card)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1c245c")
	style.border_color = Color("f8d030")
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	for edge in ["left", "right", "top", "bottom"]:
		style.set("content_margin_" + edge, 18.0)
	card.add_theme_stylebox_override("panel", style)
	copy = VBoxContainer.new()
	copy.add_theme_constant_override("separation", 10)
	card.add_child(copy)
	progress = label(copy, "", 20)
	progress.modulate = Color("75e4c8")
	chapter = label(copy, "", 23)
	chapter.modulate = Color("ffdc92")
	dialogue = label(copy, "", 26)
	dialogue.add_theme_font_override("font", preload("res://assets/fonts/arcade-ui.tres"))
	autoplay_bar = ProgressBar.new()
	autoplay_bar.custom_minimum_size.y = 5
	autoplay_bar.show_percentage = false
	autoplay_bar.max_value = 1.0
	var track := StyleBoxFlat.new()
	track.bg_color = Color("354371")
	autoplay_bar.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("f8d030")
	autoplay_bar.add_theme_stylebox_override("fill", fill)
	copy.add_child(autoplay_bar)
	next = sim.ui.button(copy, "Autoplay / Next dialogue", advance)
	next.add_theme_font_size_override("font_size", 28)
	cinematic = ColorRect.new()
	cinematic.color = Color("080d20")
	cinematic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cinematic.z_index = 10
	add_child(cinematic)
	cinematic_art = TextureRect.new()
	cinematic_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cinematic_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cinematic_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cinematic.add_child(cinematic_art)
	var shade := ColorRect.new()
	shade.color = Color(0.015, .025, .06, .16)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cinematic.add_child(shade)
	cinematic_sparks = CPUParticles2D.new()
	cinematic_sparks.amount = 36
	cinematic_sparks.lifetime = 6
	cinematic_sparks.preprocess = 6
	cinematic_sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	cinematic_sparks.direction = Vector2.UP
	cinematic_sparks.gravity = Vector2.ZERO
	cinematic_sparks.initial_velocity_min = 4
	cinematic_sparks.initial_velocity_max = 12
	cinematic_sparks.scale_amount_min = 1
	cinematic_sparks.scale_amount_max = 2.5
	cinematic_sparks.color = Color(1, .8, .4, .65)
	cinematic_sparks.emitting = false
	cinematic.add_child(cinematic_sparks)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.anchor_bottom = .64
	cinematic.add_child(center)
	cinematic_text = VBoxContainer.new()
	cinematic_text.add_theme_constant_override("separation", 30)
	center.add_child(cinematic_text)
	cinematic_title = label(cinematic_text, "CAUSEWAYBAY\nDRONE", 64)
	cinematic_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	cinematic_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	cinematic_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cinematic_title.add_theme_font_override("font", preload("res://assets/fonts/retro-title.tres"))
	cinematic_title.modulate = Color("ffe4a3")
	cinematic_title.add_theme_color_override("font_shadow_color", Color("6e471f"))
	cinematic_title.add_theme_constant_override("shadow_offset_y", 5)
	var tagline := label(cinematic_text, "AI DRONE SIMULATOR", 28)
	tagline.autowrap_mode = TextServer.AUTOWRAP_OFF
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.modulate = Color("89ded5")
	cinematic.hide()
	visible = false


func open() -> void:
	busy = false
	modulate.a = 1.0
	cinematic.hide()
	card.modulate.a = 1.0
	previous_menu = sim.ui.menu_open
	sim.ui.menu_open = true
	page = 0
	clock = 0.0
	show()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	show_page()


func close() -> void:
	if cinematic_tween:
		cinematic_tween.kill()
	if art_tween:
		art_tween.kill()
	cinematic_sparks.emitting = false
	cinematic.hide()
	if fade:
		fade.kill()
	busy = false
	hide()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	sim.ui.menu_open = previous_menu


func show_page() -> void:
	page_clock = 0.0
	if is_instance_valid(sim.sound_effects):
		sim.sound_effects.play_effect("pickup", Vector3.ZERO, true, true)
	chapter.text = tr(CHAPTERS[page][0])
	dialogue.text = tr(CHAPTERS[page][1])
	dialogue.visible_ratio = 0.0
	progress.text = "%02d / %02d" % [page + 1, CHAPTERS.size()]
	chapter.add_theme_font_override("font", preload("res://assets/fonts/arcade-ui.tres"))
	chapter.add_theme_font_size_override("font_size", 36)
	actors[1].visible = page >= 2
	actors[2].visible = page >= 2
	parcel.visible = page >= 1
	revealed = false
	copy.modulate.a = .0
	if fade:
		fade.kill()
	fade = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	fade.tween_property(copy, "modulate:a", 1.0, .3)
	fade.tween_property(dialogue, "visible_ratio", 1.0, 1.6).set_trans(Tween.TRANS_LINEAR)
	fade.tween_callback(func(): revealed = true)


func advance() -> void:
	if busy:
		return
	if not revealed:
		if fade:
			fade.kill()
		copy.modulate.a = 1.0
		dialogue.visible_ratio = 1.0
		revealed = true
		return
	if page + 1 < CHAPTERS.size():
		page += 1
		show_page()
	else:
		play_title_reveal()


func play_title_reveal() -> void:
	if busy:
		return
	busy = true
	if fade:
		fade.kill()
	cinematic.show()
	cinematic_sparks.emitting = true
	cinematic_art.scale = Vector2.ONE * 1.06
	art_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	art_tween.tween_property(cinematic_art, "scale", Vector2.ONE, 9.0)
	cinematic.modulate.a = 0.0
	cinematic_text.modulate.a = 0.0
	cinematic_text.scale = Vector2.ONE * .92
	cinematic_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	cinematic_tween.tween_property(cinematic, "modulate:a", 1.0, 1.3)
	cinematic_tween.tween_property(cinematic_text, "modulate:a", 1.0, 2.8)
	cinematic_tween.parallel().tween_property(cinematic_text, "scale", Vector2.ONE, 2.8)
	cinematic_tween.tween_interval(2.5)
	cinematic_tween.tween_property(cinematic_text, "modulate:a", 0.0, 1.6)
	cinematic_tween.parallel().tween_property(cinematic_text, "scale", Vector2.ONE * 1.04, 1.6)
	cinematic_tween.tween_callback(finish_title_reveal)


func finish_title_reveal() -> void:
	if sim.ui.title_visible:
		await sim.ui.begin_field_trial()
		sim.opening_rig.begin(sim)
	if not visible or not busy:
		return
	# Fade the complete story overlay away after the simulation is ready.
	cinematic_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	cinematic_tween.tween_property(self, "modulate:a", 0.0, 1.8)
	cinematic_tween.tween_callback(close)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE:
			advance()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()


func page_duration() -> float:
	return 1.9 + clampf(float(tr(CHAPTERS[page][1]).length()) / 22.0, 3.5, 8.0)


func advance_autoplay(delta: float) -> void:
	if not visible or busy:
		return
	page_clock += delta
	if page_clock >= page_duration():
		revealed = true
		advance()


func _process(delta: float) -> void:
	if not visible:
		return
	advance_autoplay(delta)
	if not visible:
		return
	cinematic_title.add_theme_font_size_override("font_size", int(clampf(size.x * .065, 36, 76)))
	cinematic_text.pivot_offset = cinematic_text.size * .5
	cinematic_art.texture = (
		preload("res://assets/title-cinematic-portrait-codex.png")
		if size.x < size.y
		else preload("res://assets/title-cinematic-wide-codex.png")
	)
	cinematic_art.pivot_offset = size * .5
	cinematic_sparks.position = size * .5
	cinematic_sparks.emission_rect_extents = size * .5
	clock += delta
	for i in robot_arms.size():
		robot_arms[i].rotation.x = -.55 + sin(clock * 2.0 + i) * .25
	for blade in blades:
		blade.rotation.y += delta * 30.0
	var portrait := size.x < size.y
	heading.position = Vector2(24, 24)
	heading.size.x = size.x - 48
	heading.add_theme_font_size_override("font_size", 18 if portrait else 26)
	subtitle.position = Vector2(24, 67)
	subtitle.size.x = size.x - 48
	orientation.text = tr("Vertical") if portrait else tr("Horizontal")
	card.size = Vector2(size.x - 48, 0)
	card.position = Vector2(24, size.y - card.size.y - 24)
	view.size = Vector2(size.x, maxf(160, card.position.y + 20))
	dialogue.add_theme_font_size_override(
		"font_size", 28 if sim.locale in ["ko", "ja", "zh_CN", "yue_HK"] else 34
	)
	autoplay_bar.value = clampf(page_clock / page_duration(), 0, 1)
	var shot_t := .5 - .5 * cos(PI * clampf(page_clock / page_duration(), 0, 1))
	var centers := [
		Vector3(0, 1.2, -1),
		Vector3(-1.2, 1.35, 0),
		Vector3(1.1, 1.35, .2),
		Vector3(3.0, 1.25, -1.2),
		Vector3(.2, 1.3, -.4)
	]
	var starts := [
		Vector3(-3.0, 3.0, 11),
		Vector3(-2.0, 1.0, 5.5),
		Vector3(2.5, 1.0, 5.6),
		Vector3(2.0, 1.1, 5),
		Vector3(-2, 2, 8)
	]
	var ends := [
		Vector3(-1.2, 2.3, 9),
		Vector3(-.8, .6, 4.8),
		Vector3(.9, .6, 4.8),
		Vector3(.4, .7, 4.3),
		Vector3(1.8, 3.1, 11)
	]
	var shot_offset: Vector3 = starts[page].lerp(ends[page], shot_t)
	if portrait:
		shot_offset *= 1.35
	focus = focus.lerp(centers[page], 1.0 - exp(-2.0 * delta))
	var desired := focus + shot_offset
	camera.position = camera.position.lerp(desired, 1.0 - exp(-2.0 * delta))
	camera.look_at(focus)
	actors[2].position = actors[2].position.lerp(
		Vector3(1.8 if page == 3 else 0.0, 2.2, -.4), 1.0 - exp(-2.0 * delta)
	)
	actors[2].position.y += sin(clock * 1.8) * .008
	actors[2].rotation.y = sin(clock * .5) * .12
	actors[0].rotation.y = sin(clock * .5) * .05
	actors[1].rotation.y = -.18 + sin(clock * .7) * .08
	var handoff_t := smoothstep(.1, .65, clampf(page_clock / page_duration(), 0, 1))
	parcel.position = Vector3(-4, 1.58, -2.6)
	if page == 2:
		parcel.position = Vector3(1.3, 1.15, .85)
	elif page >= 3:
		parcel.position = Vector3(1.8, 1.85, -.4).lerp(
			Vector3(3.3, 1.03, -.95), handoff_t if page == 3 else 1.0
		)
	for person_index in [3, 4]:
		var person: Node3D = actors[person_index]
		person.position.y = sin(clock * 1.5 + person_index) * .008
		var head := person.find_child("HeadPivot", true, false)
		if head:
			head.rotation.y = sin(clock * .7 + person_index) * .1
		if person_index == 4:
			for arm_name in ["Arm_L", "Arm_R"]:
				var arm := person.find_child(arm_name, true, false)
				if arm:
					arm.rotation.x = -.95 * handoff_t if page == 3 else -.95 if page == 4 else 0.0
		if person_index == 4 and page == 3:
			person.position.y += absf(sin(clock * 4)) * .07 * handoff_t
