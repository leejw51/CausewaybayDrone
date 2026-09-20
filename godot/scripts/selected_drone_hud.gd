extends Control

var sim: Node
var panel: PanelContainer
var title: Label
var battery: ProgressBar
var details: Label
var job_label: Label
var orbit_hint: Label
var selected_index := -1
var timer := 0.0
var transition: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.025, .075, .10, .94)
	style.border_color = Color("73dbc3")
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	for edge in ["left", "right", "top", "bottom"]:
		style.set("content_margin_" + edge, 12.0)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	title = make_label(column, 24)
	title.modulate = Color("ffcf78")
	battery = ProgressBar.new()
	battery.custom_minimum_size.y = 16
	battery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(battery)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("6edabf")
	battery.add_theme_stylebox_override("fill", fill)
	details = make_label(column, 18)
	job_label = make_label(column, 18)
	job_label.modulate = Color("bcd9e2")
	orbit_hint = make_label(column, 18)
	orbit_hint.text = "Drag mouse: orbit / Wheel: zoom"
	orbit_hint.modulate = Color("ffcf78")


func make_label(parent: Node, pixels: int) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", preload("res://assets/fonts/arcade-ui.tres"))
	label.add_theme_font_size_override("font_size", pixels)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func refresh() -> void:
	orbit_hint.visible = (
		sim.focus_kind == "drone"
		and not sim.first_person
		and not sim.free_camera
		and not sim.random_camera
	)
	var index: int = sim.ui.drone_list.selected
	var vehicles: Array = sim.state.get("vehicles", [])
	if index < 0 or index >= vehicles.size():
		panel.hide()
		selected_index = -1
		return
	panel.show()
	if index != selected_index:
		selected_index = index
		if transition:
			transition.kill()
		panel.modulate.a = .2
		transition = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
		transition.tween_property(panel, "modulate:a", 1.0, .2)
	var drone: Dictionary = vehicles[index]
	title.text = tr("DRONE %02d") % (index + 1) + " / " + tr(drone.state)
	battery.value = clampf(float(drone.battery), 0.0, 100.0)
	var fill: StyleBoxFlat = battery.get_theme_stylebox("fill")
	fill.bg_color = Color("ffad70") if drone.battery < 25 else Color("6edabf")
	var speed: float = sim.vec(drone.velocity).length()
	var position: Vector3 = sim.vec(drone.position)
	var altitude: float = position.y - sim.park.ground_height(position.x, position.z)
	var health: float = drone.get("maintenance", {}).get("health", 100.0)
	details.text = (
		tr("Speed %.1f m/s / Height %.1f m\nPayload %.2f kg / Health %.0f%%")
		% [speed, altitude, drone.payload, health]
	)
	var job := int(drone.job)
	job_label.text = tr("No active delivery")
	if job >= 0 and job < sim.orders.size():
		var order: Dictionary = sim.orders[job]
		job_label.text = (
			"#%03d %s / %s" % [order.id, tr(order.item), sim.customer_name(order.human)]
		)
	if not sim.transport.connected():
		job_label.text = tr("Connection lost / last received data")


func _process(delta: float) -> void:
	visible = (
		not sim.opening_rig.active
		and not sim.ui.title_visible
		and not sim.ui.menu_open
		and not sim.ui.details_open
	)
	if not visible:
		return
	modulate.a = sim.ui.hud_alpha
	var portrait := size.x < size.y
	var width := size.x - 48.0 if portrait else minf(350.0, size.x - 48.0)
	panel.size = Vector2(width, 0)
	panel.position = Vector2(
		24.0 if portrait else size.x - width - 24.0,
		sim.ui.metrics.position.y + sim.ui.metrics.size.y + 16.0
	)
	timer += delta
	if timer >= .1 or selected_index != sim.ui.drone_list.selected:
		timer = 0.0
		refresh()
