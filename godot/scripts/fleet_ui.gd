extends Control
var sim: Node3D
var title_visible := true
var launching := false
var menu_open := false
var hud_alpha := 0.0
var fades: Dictionary = {}
var page_tween: Tween
var displayed_page := 0
var pending_page := 0
var menu: PanelContainer
var title_backdrop: TextureRect
var title_panel: ColorRect
var mode: OptionButton
var language: OptionButton
var effects_toggle: CheckBox
var effects_volume: HSlider
var effects_dragging := false
var autonomy: CheckBox
var drone_count: SpinBox
var cafe_count: SpinBox
var human_count: SpinBox
var item: OptionButton
var quantity: SpinBox
var customer: OptionButton
var cafe: OptionButton
var location: OptionButton
var drone_list: OptionButton
var status_label: Label
var orders_label: Label
var inspector: VBoxContainer
var inspector_page: OptionButton
var inspector_scroll: ScrollContainer
var toolbar: HFlowContainer
var metrics: Label
var start_button: Button
var connection_label: Label
var last_count := -1
var telemetry_refresh := 0.0
var story: Control
var dashboard: Control
var random_button: Button
var director_toggle: CheckBox
var pages: TabContainer
var details_open := false
var apply_counts_button: Button
var count_feedback: Label
var title_layout_button: Button
var fullscreen_button: Button
var windowed_size := Vector2i(1280, 800)
const DISPLAY_PREFS = preload("res://scripts/frontend_preferences.gd")
var display_saved := {}
var display_candidate := {}
var display_changed_at := 0
var display_ready := false
var layout_button: Button
var pause_button: Button
var order_feedback: Label
var order_button: Button


func new_page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pages.add_child(scroll)
	var contents := VBoxContainer.new()
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_theme_constant_override("separation", 14)
	scroll.add_child(contents)
	if title != "Play":
		button(contents, "Back", func(): open_page(3))
	return contents


func open_page(index: int) -> void:
	pages.current_tab = index
	set_menu_visible(true)


static func operations_rect(viewport: Vector2, top: float) -> Rect2:
	var bottom := viewport.y - 70.0
	if viewport.x < viewport.y:
		var height := minf(clampf(viewport.y * .34, 180.0, 340.0), maxf(80.0, bottom - top))
		return Rect2(24.0, bottom - height, maxf(1.0, viewport.x - 48.0), height)
	return Rect2(viewport.x - 330.0, top, 305.0, maxf(80.0, bottom - top))


func toggle_layout() -> void:
	var portrait := get_window().size.x < get_window().size.y
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 800) if portrait else Vector2i(650, 900)
	windowed_size = get_window().size
	get_window().move_to_center()
	save_display_preferences()


func focus_nature(rabbit: bool) -> void:
	sim.set_free_camera(false)
	sim.random_camera = false
	sim.director = false
	sim.first_person = false
	sim.focus_kind = "nature"
	sim.focus_index = 0
	if rabbit:
		for i in sim.park.wildlife.targets.size():
			if str(sim.park.wildlife.targets[i].node.name).begins_with("Rabbit"):
				sim.focus_index = i
				break
	sim.zoom = 3.5 if rabbit else 30.0
	sim.orbit = .1
	sim.elevation = .15 if rabbit else -.075
	set_menu_visible(false)


func wait_for_config_state(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline and sim.transport.connected():
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func apply_counts() -> void:
	if apply_counts_button.disabled:
		return
	for field in [drone_count, cafe_count, human_count]:
		field.apply()
	var d := int(drone_count.value)
	var c := int(cafe_count.value)
	var h := int(human_count.value)
	var auto_orders := autonomy.button_pressed
	var resume: bool = sim.running
	apply_counts_button.disabled = true
	count_feedback.text = tr("Applying counts...")
	if resume:
		sim.send({"command": "stop"})
		if not await wait_for_config_state(func(): return not sim.running):
			count_feedback.text = tr(
				"Could not apply counts. Check the backend connection and retry."
			)
			apply_counts_button.disabled = false
			return
	var previous_run: String = sim.state.get("run_id", "")
	# Solo is a preset, never a reason to discard explicitly entered counts.
	var chosen_mode := "Solo" if d == 1 and c == 1 and h == 1 else "Massive"
	sim.configure(d, c, h, chosen_mode, auto_orders)
	var applied := await wait_for_config_state(
		func(): return sim.state.get("run_id", "") != previous_run
	)
	if applied:
		count_feedback.text = tr("Counts applied: %d drones / %d shops / %d customers") % [d, c, h]
		if resume:
			sim.send({"command": "start"})
	else:
		count_feedback.text = tr("Could not apply counts. Check the backend connection and retry.")
	apply_counts_button.disabled = false


func toggle_fullscreen() -> void:
	var window := get_window()
	if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
		window.mode = Window.MODE_WINDOWED
		window.size = windowed_size
		window.move_to_center()
	else:
		windowed_size = window.size
		window.mode = Window.MODE_FULLSCREEN
	save_display_preferences()


func display_preferences() -> Dictionary:
	var window := get_window()
	if window.mode == Window.MODE_WINDOWED:
		windowed_size = window.size
	return {
		"schema": 1,
		"window_mode":
		(
			"fullscreen"
			if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
			else "windowed"
		),
		"orientation": "vertical" if windowed_size.x < windowed_size.y else "horizontal",
		"window_size": [windowed_size.x, windowed_size.y]
	}


func save_display_preferences() -> void:
	if not display_ready:
		return
	var value := display_preferences()
	if value == display_saved:
		return
	var error := DISPLAY_PREFS.append(value)
	if error == OK:
		display_saved = value
	else:
		push_warning("Could not save frontend.jsonl: " + error_string(error))


func restore_display_preferences() -> void:
	var value := DISPLAY_PREFS.read_latest()
	if not value.is_empty():
		var window := get_window()
		windowed_size = Vector2i(value.window_size[0], value.window_size[1])
		window.mode = Window.MODE_WINDOWED
		window.size = windowed_size
		window.move_to_center()
		if value.window_mode == "fullscreen":
			window.mode = Window.MODE_FULLSCREEN
		display_saved = value.duplicate(true)
		display_saved.erase("saved_at")
	display_ready = true
	save_display_preferences()


func track_display_preferences() -> void:
	if not display_ready:
		return
	var value := display_preferences()
	if value != display_candidate:
		display_candidate = value
		display_changed_at = Time.get_ticks_msec()
	elif Time.get_ticks_msec() - display_changed_at >= 400:
		save_display_preferences()


func button(parent: Node, title: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = title
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 36
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func label(parent: Node, title: String, size_px := 16) -> Label:
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", size_px)
	parent.add_child(l)
	return l


func row(parent: Node, title: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	parent.add_child(h)
	var l := label(h, title)
	l.custom_minimum_size.x = 120
	return h


func spin(parent: Node, max_value: int, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 1
	s.max_value = max_value
	s.value = value
	s.custom_minimum_size.x = 130
	parent.add_child(s)
	return s


func options(parent: Node, items: Array) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for text in items:
		o.add_item(tr(text))
		o.set_item_metadata(o.item_count - 1, text)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.custom_minimum_size.y = 34
	parent.add_child(o)
	return o


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme_new := Theme.new()
	theme_new.default_font = preload("res://assets/fonts/arcade-ui.tres")
	theme_new.default_font_size = 22
	theme_new.set_font_size("font_size", "Button", 22)
	theme_new.set_font_size("font_size", "OptionButton", 22)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1c245c")
	style.set_corner_radius_all(12)
	style.set_border_width_all(2)
	style.border_color = Color("f8d030")
	style.shadow_color = Color("102737")
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 3)
	style.content_margin_left = 13
	style.content_margin_right = 13
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	theme_new.set_stylebox("normal", "Button", style)
	var hover := style.duplicate()
	hover.bg_color = Color("b06828")
	hover.border_color = Color("ffd37a")
	theme_new.set_stylebox("hover", "Button", hover)
	for kind in ["Button", "OptionButton"]:
		theme_new.set_stylebox("normal", kind, style)
		theme_new.set_stylebox("hover", kind, hover)
		var pressed := style.duplicate()
		pressed.bg_color = Color("387d83")
		theme_new.set_stylebox("pressed", kind, pressed)
		theme_new.set_color("font_color", kind, Color("edf5ed"))
	theme = theme_new
	toolbar = HFlowContainer.new()
	toolbar.position = Vector2(24, 20)
	toolbar.add_theme_constant_override("h_separation", 8)
	toolbar.add_theme_constant_override("v_separation", 8)
	add_child(toolbar)
	button(toolbar, "Menu", func(): open_page(3))
	pause_button = button(
		toolbar,
		"Start",
		func():
			if sim.running:
				sim.send({"command": "stop"})
			else:
				sim.start_simulation()
	)
	drone_list = options(toolbar, [])
	drone_list.custom_minimum_size.x = 180
	drone_list.item_selected.connect(
		func(index):
			sim.set_free_camera(false)
			sim.focus_kind = "drone"
			sim.focus_index = index
			sim.director = false
	)
	var views := options(
		toolbar,
		["Follow drone", "Drone cockpit", "Shop", "Customer", "Auto camera", "Free camera [F]"]
	)
	views.item_selected.connect(
		func(index):
			sim.set_free_camera(index == 5)
			sim.director = index == 4
			sim.first_person = index == 1
			sim.focus_index = maxi(0, drone_list.selected) if index < 2 else 0
			sim.focus_kind = "drone" if index < 2 else "cafe" if index == 2 else "human"
			sim.zoom = 12 if index < 2 else 18
			set_menu_visible(false)
	)
	button(
		toolbar,
		"Instant charge",
		func(): sim.send({"command": "instant_charge", "drone": drone_list.selected})
	)
	random_button = button(
		toolbar,
		"Random Camera",
		func():
			if sim.random_camera:
				sim.random_camera = false
			else:
				sim.start_random_camera()
	)
	random_button.toggle_mode = true
	var details_button := button(toolbar, "Details", func(): details_open = not details_open)
	layout_button = button(toolbar, "Horizontal", toggle_layout)
	layout_button.toggle_mode = true
	metrics = Label.new()
	metrics.position = Vector2(24, 68)
	metrics.add_theme_font_size_override("font_size", 18)
	add_child(metrics)
	menu = PanelContainer.new()
	menu.position = Vector2(22, 110)
	menu.custom_minimum_size = Vector2(380, 0)
	var panelstyle := StyleBoxFlat.new()
	panelstyle.bg_color = Color(.11, .14, .36, .97)
	panelstyle.border_color = Color("f8d030")
	panelstyle.set_border_width_all(3)
	panelstyle.set_corner_radius_all(12)
	panelstyle.content_margin_left = 20
	panelstyle.content_margin_right = 20
	panelstyle.content_margin_top = 16
	panelstyle.content_margin_bottom = 16
	menu.add_theme_stylebox_override("panel", panelstyle)
	add_child(menu)
	pages = TabContainer.new()
	pages.tabs_visible = false
	pages.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	pages.custom_minimum_size = Vector2(350, 360)
	menu.add_child(pages)
	var column := new_page("Settings")
	button(column, "Close  ×", func(): set_menu_visible(false))
	button(column, "Story", func(): story.open())
	label(column, "Your simulation", 24)
	language = options(row(column, "Language"), preload("res://scripts/localization.gd").NAMES)
	language.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	language.item_selected.connect(
		func(index):
			sim.send(
				{
					"command": "language",
					"language": preload("res://scripts/localization.gd").CODES[index]
				}
			)
	)
	mode = options(row(column, "Mode"), ["Solo", "Massive"])
	mode.select(1)
	drone_count = spin(row(column, "Drones"), 32, 8)
	cafe_count = spin(row(column, "Shops"), 12, 3)
	human_count = spin(row(column, "Customers"), 200, 20)
	mode.item_selected.connect(
		func(index):
			if index == 0:
				drone_count.value = 1
				cafe_count.value = 1
				human_count.value = 1
			else:
				drone_count.value = 8
				cafe_count.value = 3
				human_count.value = 20
	)
	apply_counts_button = button(column, "NEW SIMULATION / APPLY COUNTS", apply_counts)
	count_feedback = label(
		column, "Applying counts starts a new run and resets current orders.", 16
	)
	count_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	autonomy = CheckBox.new()
	autonomy.text = "AUTONOMOUS / people order automatically"
	autonomy.button_pressed = true
	autonomy.toggled.connect(
		func(enabled):
			if not sim.state.get("vehicles", []).is_empty():
				sim.send({"command": "autonomy", "enabled": enabled})
	)
	column.add_child(autonomy)
	column = new_page("Orders")
	button(column, "Close  ×", func(): set_menu_visible(false))
	label(column, "Send a delivery", 24)
	label(column, "Choose a meal and destination.", 15)
	item = options(row(column, "Menu"), ["Sandwich", "Coffee", "Sandwich + Coffee"])
	quantity = spin(row(column, "Quantity"), 3, 1)
	customer = options(row(column, "Customer"), [])
	cafe = options(row(column, "Shop"), [])
	cafe.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	customer.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	location = options(row(column, "Receive at"), ["Outside", "Apartment balcony"])
	order_button = button(
		column,
		"Place order",
		func():
			sim.place_order(
				item.get_item_metadata(item.selected),
				int(quantity.value),
				customer.selected,
				cafe.selected,
				location.selected == 1
			)
	)
	button(column, "Order for everyone", func(): sim.send({"command": "batch"}))
	order_feedback = label(column, "", 15)
	order_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	order_feedback.custom_minimum_size.x = 280
	column = new_page("Fleet")
	button(column, "Close  ×", func(): set_menu_visible(false))
	label(column, "Explore & service", 24)
	label(column, "PARK WILDLIFE", 18)
	button(
		column,
		"LONE TREE",
		func():
			sim.set_free_camera(false)
			sim.focus_kind = "nature"
			sim.focus_index = 0
			sim.first_person = false
			sim.director = false
			sim.zoom = 30
			sim.orbit = .1
			sim.elevation = -.075
			set_menu_visible(false)
	)
	button(
		column,
		"WATCH CATS / RABBITS",
		func():
			sim.set_free_camera(false)
			sim.focus_kind = "nature"
			sim.focus_index = 1 + (sim.focus_index % 9)
			sim.first_person = false
			sim.director = false
			sim.zoom = 3.5
			sim.elevation = .15
			set_menu_visible(false)
	)
	label(column, "FIELD TRIAL OBSERVATION", 20)
	director_toggle = CheckBox.new()
	director_toggle.text = "Director camera"
	director_toggle.toggled.connect(func(value): sim.director = value)
	column.add_child(director_toggle)
	label(column, "FLEET SERVICE", 20)
	button(
		column,
		"CHARGE SELECTED DRONE",
		func(): sim.send({"command": "service", "drone": drone_list.selected, "reason": "charge"})
	)
	button(
		column,
		"REPAIR SELECTED DRONE",
		func(): sim.send({"command": "service", "drone": drone_list.selected, "reason": "repair"})
	)
	button(
		column,
		"SIMULATE DRONE FAULT",
		func(): sim.send({"command": "fault", "drone": drone_list.selected})
	)
	button(
		column,
		"VIEW SERVICE DOCK",
		func():
			sim.set_free_camera(false)
			sim.focus_kind = "dock"
			sim.focus_index = maxi(0, drone_list.selected)
			sim.first_person = false
			sim.zoom = 12
	)
	column = pages.get_child(0).get_child(0)
	label(column, "Audio", 20)
	effects_toggle = CheckBox.new()
	effects_toggle.text = "Sound effects"
	effects_toggle.button_pressed = true
	column.add_child(effects_toggle)
	effects_volume = HSlider.new()
	effects_volume.min_value = 0
	effects_volume.max_value = 100
	effects_volume.step = 1
	effects_volume.value = 65
	effects_volume.custom_minimum_size.x = 150
	row(column, "Effects volume").add_child(effects_volume)
	effects_toggle.toggled.connect(func(_value): save_sound())
	effects_volume.drag_started.connect(func(): effects_dragging = true)
	effects_volume.drag_ended.connect(
		func(changed):
			effects_dragging = false
			if changed:
				save_sound()
	)
	effects_volume.value_changed.connect(
		func(_value):
			if not effects_dragging:
				save_sound()
	)
	var voice := CheckBox.new()
	voice.text = "Drone voice announcements"
	voice.button_pressed = true
	voice.toggled.connect(func(value): sim.speech = value)
	column.add_child(voice)
	connection_label = label(column, "Connecting...", 13)
	status_label = label(column, "", 13)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.x = 330
	inspector = VBoxContainer.new()
	add_child(inspector)
	inspector_page = options(
		inspector, ["OPERATIONS", "SHOPS / QUEUES", "CUSTOMERS", "LIVE ORDERS"]
	)
	inspector_scroll = ScrollContainer.new()
	inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector.add_child(inspector_scroll)
	orders_label = Label.new()
	orders_label.add_theme_font_size_override("font_size", 14)
	orders_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orders_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	orders_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_scroll.add_child(orders_label)
	var play_menu := new_page("Play")
	label(play_menu, "Adventure menu", 34).modulate = Color("f8d030")
	button(play_menu, "Resume flight", func(): set_menu_visible(false))
	button(play_menu, "Orders", func(): open_page(1))
	button(play_menu, "Fleet", func(): open_page(2))
	button(play_menu, "Dashboard", func(): dashboard.open())
	button(play_menu, "Settings", func(): open_page(0))
	button(play_menu, "Story", func(): story.open())
	button(play_menu, "Camera to rabbit", func(): focus_nature(true))
	button(play_menu, "Camera to lone tree", func(): focus_nature(false))
	views.reparent(play_menu)
	random_button.reparent(play_menu)
	details_button.reparent(play_menu)
	details_button.pressed.connect(func(): set_menu_visible(false))
	for entry in play_menu.get_children():
		if entry is Button:
			entry.custom_minimum_size.y = 46
			entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
			entry.add_theme_font_size_override("font_size", 28)
			var flat := StyleBoxFlat.new()
			flat.bg_color = Color(0, 0, 0, 0)
			flat.content_margin_left = 18
			entry.add_theme_stylebox_override("normal", flat)
			var highlight := flat.duplicate()
			highlight.bg_color = Color("f8d030")
			highlight.set_corner_radius_all(8)
			entry.add_theme_stylebox_override("hover", highlight)
			entry.add_theme_stylebox_override("focus", highlight)
			entry.add_theme_color_override("font_hover_color", Color("1c245c"))
			entry.add_theme_color_override("font_focus_color", Color("1c245c"))
			entry.focus_mode = Control.FOCUS_ALL
	title_panel = ColorRect.new()
	title_panel.color = Color("071b20")
	title_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(title_panel)
	var backdrop := TextureRect.new()
	title_backdrop = backdrop
	backdrop.texture = preload("res://assets/title-cinematic-wide-codex.png")
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_panel.add_child(backdrop)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.04, 0.06, .56)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_panel.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 64)
	title_panel.add_child(margin)
	var titles := VBoxContainer.new()
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", 12)
	margin.add_child(titles)
	label(titles, "A LITTLE PARK. A BIG ADVENTURE.", 26).modulate = Color("65dfc8")
	label(titles, "CAUSEWAYBAY\nDRONE", 42).add_theme_font_override(
		"font", preload("res://assets/fonts/retro-title.tres")
	)
	label(titles, "OLYMPIC PARK · AUTONOMOUS FIELD TRIAL", 24)
	label(titles, "Causewaybay Rust Coder", 28)
	label(titles, "Your park. Your fleet. Let the deliveries begin.", 24)
	label(titles, "Sandwiches, coffee, and little adventures.", 24)
	button(titles, "Story", func(): story.open()).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var launch := button(titles, "START ADVENTURE", func(): story.open())
	launch.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var display_modes := HFlowContainer.new()
	display_modes.add_theme_constant_override("h_separation", 12)
	display_modes.add_theme_constant_override("v_separation", 8)
	titles.add_child(display_modes)
	title_layout_button = button(display_modes, "Horizontal", toggle_layout)
	title_layout_button.toggle_mode = true
	fullscreen_button = button(display_modes, "Windowed", toggle_fullscreen)
	fullscreen_button.toggle_mode = true
	label(titles, "PRESS SPACEKEY TO CONTINUE", 26).modulate = Color("f8d030")
	label(titles, "HAPPY CUSTOMERS  /  ROBOT CHEFS  /  FLYING FRIENDS", 20)
	story = preload("res://scripts/title_story.gd").new()
	story.sim = sim
	add_child(story)
	dashboard = preload("res://scripts/dashboard.gd").new()
	dashboard.sim = sim
	add_child(dashboard)
	toolbar.visible = false
	menu.visible = false
	metrics.visible = false
	inspector.visible = false
	restore_display_preferences()


func begin_field_trial() -> void:
	if not title_visible or launching:
		return
	launching = true
	await sim.autonomous_start()
	launching = false


func fade_control(control: Control, shown: bool, seconds := .30) -> void:
	if fades.has(control) and is_instance_valid(fades[control]):
		fades[control].kill()
	if shown and not control.visible:
		control.modulate.a = 0.0
		control.show()
	# Disable the fading-out subtree so invisible controls cannot take input.
	var controls: Array[Node] = [control]
	controls.append_array(control.find_children("*", "Control", true, false))
	for node in controls:
		if not node.has_meta("fade_mouse_filter"):
			node.set_meta("fade_mouse_filter", node.mouse_filter)
		node.mouse_filter = (
			node.get_meta("fade_mouse_filter") if shown else Control.MOUSE_FILTER_IGNORE
		)
		if not shown:
			node.release_focus()
		if node is BaseButton:
			if not node.has_meta("fade_disabled"):
				node.set_meta("fade_disabled", node.disabled)
			node.disabled = node.get_meta("fade_disabled") if shown else true
	var tween := create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	fades[control] = tween
	tween.tween_property(control, "modulate:a", 1.0 if shown else 0.0, seconds)
	if not shown:
		tween.tween_callback(control.hide)


func set_menu_visible(shown: bool) -> void:
	menu_open = shown
	fade_control(menu, shown)
	if shown and pages.current_tab == 3:
		pages.get_child(3).get_child(0).get_child(1).grab_focus()


func toggle_menu() -> void:
	if not menu_open:
		pages.current_tab = 3
	set_menu_visible(not menu_open)


func show_menu() -> void:
	if title_visible:
		title_visible = false
		fade_control(title_panel, false, .42)
		for panel in [toolbar, metrics, inspector]:
			fade_control(panel, true, .42)
		create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT).tween_property(
			self, "hud_alpha", 1.0, .42
		)
	set_menu_visible(true)


func transition_page(index: int) -> void:
	pending_page = index
	if is_instance_valid(page_tween):
		page_tween.kill()
	page_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	page_tween.tween_property(orders_label, "modulate:a", 0.0, .14)
	page_tween.tween_callback(func(): displayed_page = index)
	page_tween.tween_property(orders_label, "modulate:a", 1.0, .22)


func sync_config() -> void:
	autonomy.set_pressed_no_signal(sim.config.get("auto_orders", true))
	drone_count.value = sim.config.drones
	cafe_count.value = sim.config.cafes
	human_count.value = sim.config.humans
	mode.select(0 if sim.config.mode == "Solo" else 1)


func _process(_delta: float) -> void:
	track_display_preferences()
	toolbar.visible = not title_visible and not sim.opening_rig.active
	title_backdrop.texture = (
		preload("res://assets/title-cinematic-portrait-codex.png")
		if size.x < size.y
		else preload("res://assets/title-cinematic-wide-codex.png")
	)
	inspector.visible = not title_visible and details_open and not menu_open
	toolbar.size.x = size.x - 48
	var bar_height := maxf(44, toolbar.size.y)
	metrics.visible = false
	metrics.position.y = 12 + bar_height
	menu.position = Vector2(24, 65 + bar_height)
	pause_button.text = tr("Pause") if sim.running else tr("Start")
	var portrait := size.x < size.y
	layout_button.text = tr("Vertical") if portrait else tr("Horizontal")
	layout_button.set_pressed_no_signal(portrait)
	title_layout_button.text = layout_button.text
	title_layout_button.set_pressed_no_signal(portrait)
	var fullscreen := (
		get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
	)
	fullscreen_button.text = tr("Fullscreen") if fullscreen else tr("Windowed")
	fullscreen_button.set_pressed_no_signal(fullscreen)
	var area := operations_rect(size, menu.position.y + 12.0)
	inspector.position = area.position
	inspector.size = area.size
	director_toggle.set_pressed_no_signal(sim.director)
	random_button.set_pressed_no_signal(sim.random_camera)
	if inspector_page.selected != pending_page:
		transition_page(inspector_page.selected)
	menu.size = Vector2(minf(520, size.x - 48), maxf(260, size.y - menu.position.y - 60))
	# Layout and tweens stay at render rate; dashboard text needs only 10 Hz.
	queue_redraw()
	telemetry_refresh += _delta
	if telemetry_refresh < .1:
		return
	telemetry_refresh = 0.0
	if not is_instance_valid(sim.transport):
		return
	connection_label.text = (
		tr("RUST FFI / WEBSOCKET CONNECTED")
		if sim.transport.connected()
		else tr("BACKEND OFFLINE / RECONNECTING")
	)
	status_label.text = tr(sim.storage_error)
	order_button.disabled = (
		not sim.transport.connected() or sim.humans.is_empty() or sim.cafes.is_empty()
	)
	order_feedback.text = tr(sim.storage_error)
	if order_feedback.text.is_empty():
		order_feedback.text = (
			tr("Start the simulation to prepare and deliver orders.") if not sim.running else ""
		)
		for j in range(sim.orders.size() - 1, -1, -1):
			var job: Dictionary = sim.orders[j]
			if int(job.human) == customer.selected:
				order_feedback.text += "\n#%03d · %s · %s" % [job.id, tr(job.item), tr(job.state)]
				break
	var complete := 0
	for job in sim.orders:
		if job.state == "DELIVERED":
			complete += 1
	metrics.text = (
		tr("%s   ·   %d drones   ·   %d delivered")
		% [tr("RUNNING") if sim.running else tr("STOPPED"), sim.vehicles.size(), complete]
	)
	if sim.vehicles.size() != last_count:
		last_count = sim.vehicles.size()
		drone_list.clear()
		for i in last_count:
			drone_list.add_item(tr("DRONE %02d") % (i + 1))
	for i in sim.vehicles.size():
		drone_list.set_item_text(i, tr("DRONE %02d") % (i + 1))
	if customer.item_count != sim.humans.size():
		customer.clear()
		for i in sim.humans.size():
			customer.add_item(sim.customer_name(i))
	if cafe.item_count != sim.cafes.size():
		cafe.clear()
		for i in sim.cafes.size():
			cafe.add_item(sim.shop_name(i))
	var text := ""
	if displayed_page == 0:
		var active := 0
		var failed := 0
		var elapsed := 0.0
		for v in sim.vehicles:
			if v.state != "IDLE":
				active += 1
		for job in sim.orders:
			if job.state == "FAILED":
				failed += 1
			if job.state == "DELIVERED":
				elapsed += float(job.delivered) - float(job.created)
		text = (
			tr(
				"AUTONOMOUS DELIVERY SIMULATOR\n\nFleet working: %d / %d\nPending orders: %d\nDelivered: %d  |  Failed: %d\n"
			)
			% [active, sim.vehicles.size(), sim.orders.size() - complete - failed, complete, failed]
		)
		text += (
			tr("Mean fulfillment: %.1f sim seconds\n") % (elapsed / complete)
			if complete > 0
			else tr("Mean fulfillment: awaiting delivery\n")
		)
		text += tr("\nOLYMPIC PARK / GEOFENCE ACTIVE\n")
		text += tr("\nFLEET TELEMETRY\n")
		for i in sim.state.get("vehicles", []).size():
			var v: Dictionary = sim.state.vehicles[i]
			var velocity := Vector3(v.velocity[0], v.velocity[1], v.velocity[2])
			text += (
				tr("\nDRONE %02d / %s\n%.1f m/s  |  Battery %.0f%%\nPayload %.2f kg\n")
				% [i + 1, tr(v.state), velocity.length(), v.battery, v.payload]
			)

			if i == sim.focus_index:
				var origin: Dictionary = sim.park.data.origin
				var pos: Vector3 = sim.vec(v.position)
				var latitude: float = origin.lat - pos.z / origin.metres_per_lat_degree
				var longitude: float = origin.lon + pos.x / origin.metres_per_lon_degree
				var agl: float = pos.y - sim.park.ground_height(pos.x, pos.z)
				text += (
					"GPS %.6f, %.6f\nAGL %.1f m / DEM altitude %.1f m\n"
					% [latitude, longitude, agl, pos.y + float(origin.elevation_datum)]
				)
			if v.has("body"):
				var force: Array = v.body.thrust
				var thrust := Vector3(force[0], force[1], force[2]).length()
				text += tr("Mass %.2f kg / Thrust %.1f N\n") % [5.0 + float(v.payload), thrust]
			if v.has("maintenance"):
				var m: Dictionary = v.maintenance
				text += (
					tr("Health %.0f%% / Charges %d / Repairs %d\n")
					% [m.health, m.charges, m.repairs]
				)
				if m.avoiding:
					text += tr("AVOIDING TRAFFIC") + "\n"
				if v.state in ["CHARGING", "DIAGNOSING", "REPAIRING"]:
					text += tr("Service elapsed %.0f s\n") % m.elapsed
	elif displayed_page == 1:
		for i in sim.cafes.size():
			var queued := 0
			var served := 0
			for job in sim.orders:
				if int(job.cafe) == i:
					if job.state == "ORDERED":
						queued += 1
					if job.state == "DELIVERED":
						served += 1
			var job_index: int = sim.cafes[i].job
			var phase: String = sim.orders[job_index].state if job_index >= 0 else "IDLE"
			text += (
				tr("%s\nRobot: %s\nQueue: %d  |  Delivered: %d\n\n")
				% [sim.shop_name(i), tr(phase), queued, served]
			)
	elif displayed_page == 2:
		for i in sim.humans.size():
			var latest: Dictionary = {}
			for job in sim.orders:
				if int(job.human) == i:
					latest = job
			text += sim.customer_name(i) + "\n"
			if latest.is_empty():
				text += tr("No orders yet\n\n")
			else:
				text += (
					tr("%s / %s\n%s\n\n")
					% [
						tr(latest.item),
						tr(latest.state),
						(
							tr("Apartment balcony")
							if latest.get("apartment", false)
							else tr("Outdoor delivery")
						)
					]
				)
	else:
		for i in range(sim.orders.size() - 1, maxi(-1, sim.orders.size() - 101), -1):
			var j: Dictionary = sim.orders[i]
			text += (
				tr("#%03d  %s → %s\n%s × %d / %s\n\n")
				% [
					j.id,
					sim.shop_name(j.cafe),
					sim.customer_name(j.human),
					tr(j.item),
					j.quantity,
					tr(j.state)
				]
			)
	orders_label.text = text
	queue_redraw()


func _draw() -> void:
	if title_visible or sim.opening_rig.active:
		return
	var dark := Color(.02, .06, .075, .94 * hud_alpha)

	if inspector.visible:
		draw_rect(
			Rect2(inspector.position - Vector2(12, 12), inspector.size + Vector2(24, 24)), dark
		)
	if not menu_open and not details_open:
		return
	draw_rect(Rect2(12, size.y - 53, size.x - 24, 43), dark)
	draw_string(
		theme.default_font,
		Vector2(26, size.y - 34),
		(
			tr("WASD: fly · Q/E: down/up · RMB: look · Shift: boost · Wheel: speed · F: exit")
			if sim.free_camera
			else tr("RMB: orbit · Wheel: zoom · F: free fly · M: menu")
		),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		Color(Color("bdd6cc"), hud_alpha)
	)

	draw_string(
		theme.default_font,
		Vector2(26, size.y - 18),
		"© OpenStreetMap / ODbL · Mapzen / USGS · 1 unit = 1 m",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		Color(Color("bdd6cc"), hud_alpha)
	)


func refresh_language() -> void:
	language.select(
		preload("res://scripts/localization.gd").CODES.find(sim.config.get("language", "en"))
	)
	for selector in [customer, cafe]:
		if selector.item_count > 0:
			selector.select(maxi(0, selector.selected))
	for selector in [mode, item, location, inspector_page]:
		for index in selector.item_count:
			selector.set_item_text(index, tr(str(selector.get_item_metadata(index))))


func save_sound() -> void:
	sim.send(
		{
			"command": "sound",
			"enabled": effects_toggle.button_pressed,
			"volume": effects_volume.value / 100.0
		}
	)


func sync_sound() -> void:
	effects_toggle.set_pressed_no_signal(sim.config.get("sfx_enabled", true))
	if not effects_dragging:
		effects_volume.set_value_no_signal(float(sim.config.get("sfx_volume", .65)) * 100)
