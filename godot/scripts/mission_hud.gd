extends Control
var sim: Node3D
var card: PanelContainer
var heading: Label
var mission: Label
var progress: ProgressBar
var toast: Label
var score_shown := 0.0
var last_score := -1
var last_run := ""
var score_tween: Tween
var toast_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	card = PanelContainer.new()
	card.position = Vector2(430, 112)
	card.custom_minimum_size.x = 310
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.025, .09, .10, .9)
	style.border_color = Color("e9af50")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", style)
	add_child(card)
	var column := VBoxContainer.new()
	card.add_child(column)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 30)
	heading.add_theme_font_override("font", preload("res://assets/fonts/arcade-ui.tres"))
	heading.modulate = Color("ffd387")
	column.add_child(heading)
	mission = Label.new()
	mission.add_theme_font_size_override("font_size", 18)
	mission.add_theme_font_override("font", preload("res://assets/fonts/arcade-ui.tres"))
	mission.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(mission)
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 9
	progress.show_percentage = false
	column.add_child(progress)
	toast = Label.new()
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 28)
	toast.add_theme_color_override("font_shadow_color", Color.BLACK)
	toast.add_theme_constant_override("shadow_offset_x", 2)
	toast.add_theme_constant_override("shadow_offset_y", 2)
	toast.modulate = Color(1, .84, .5, 0)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast)


func celebrate(message: String) -> void:
	if is_instance_valid(toast_tween):
		toast_tween.kill()
	toast.text = message
	toast.modulate.a = 0.0
	toast_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	toast_tween.tween_property(toast, "modulate:a", 1.0, .2)
	toast_tween.tween_interval(2.0)
	toast_tween.tween_property(toast, "modulate:a", 0.0, .4)


func _process(_delta: float) -> void:
	visible = (
		not sim.opening_rig.active
		and not sim.ui.title_visible
		and sim.focus_kind != "nature"
		and not sim.ui.menu_open
		and not sim.ui.details_open
	)
	card.position = Vector2(24, size.y - 205)
	card.size.x = minf(370, size.x - 48)
	modulate.a = sim.ui.hud_alpha
	if not visible or sim.state.is_empty():
		return
	var delivered := 0
	for order in sim.orders:
		if order.state == "DELIVERED":
			delivered += 1
	heading.text = tr("OLYMPIC PARK")
	mission.text = (
		tr("%d deliveries completed · %d active orders\nPickup → Deliver → Return → Charge")
		% [delivered, sim.orders.size() - delivered]
	)
	progress.max_value = maxf(1, sim.orders.size())
	progress.value = delivered
