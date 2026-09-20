extends Control

var game: Node
var font: Font = ThemeDB.fallback_font
var primary: Button
var secondary: Button
var product: OptionButton
var quantity: SpinBox
var ink := Color("e8f1e9")
var muted := Color("a3bdb5")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	primary = button(
		"PLACE ORDER",
		func():
			if game.phase == game.Phase.BRIEFING:
				submit_order()
			elif game.phase == game.Phase.DOCKED:
				game.begin(true)
			else:
				game.restart()
	)
	secondary = button("TRAINING CAMPAIGN", func(): game.begin(true))
	product = OptionButton.new()
	for item in game.MENU:
		product.add_item(item)
	product.select(2)
	product.add_theme_font_size_override("font_size", 20)
	add_child(product)
	quantity = SpinBox.new()
	quantity.min_value = 1
	quantity.max_value = 3
	quantity.value = 1
	quantity.add_theme_font_size_override("font_size", 20)
	add_child(quantity)


func submit_order() -> void:
	game.place_order(product.selected, int(quantity.value))


func button(title: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = title
	b.add_theme_font_size_override("font_size", 18)
	for state in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color("277e70") if state == "normal" else Color("3b9b86")
		s.set_corner_radius_all(8)
		b.add_theme_stylebox_override(state, s)
	b.pressed.connect(action)
	add_child(b)
	return b


func text_at(p: Vector2, s: String, font_size := 16, color := Color("e8f1e9")) -> void:
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func panel(rect: Rect2) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(.02, .06, .07, 1.0)
	s.border_color = Color(.35, .62, .54, .55)
	s.set_border_width_all(1)
	s.set_corner_radius_all(12)
	draw_style_box(s, rect)


func _process(_delta: float) -> void:
	var menu: bool = (
		game.phase
		in [game.Phase.BRIEFING, game.Phase.DOCKED, game.Phase.COMPLETE, game.Phase.FAILED]
	)
	primary.visible = menu
	secondary.visible = menu and game.phase == game.Phase.BRIEFING
	primary.position = size * .5 + Vector2(-220, 98)
	primary.size = Vector2(440, 48)
	secondary.position = size * .5 + Vector2(-220, 158)
	secondary.size = Vector2(440, 42)
	product.visible = menu and game.phase == game.Phase.BRIEFING
	quantity.visible = product.visible
	product.position = size * .5 + Vector2(-220, -49)
	product.size = Vector2(320, 46)
	quantity.position = size * .5 + Vector2(112, -49)
	quantity.size = Vector2(108, 46)
	primary.text = "PLACE ORDER / AI DELIVERY"
	if game.phase == game.Phase.DOCKED:
		primary.text = "RESUME MISSION"
	if game.phase in [game.Phase.COMPLETE, game.Phase.FAILED]:
		primary.text = "NEW ORDER"
	queue_redraw()


func _draw() -> void:
	if not game:
		return
	var w := size.x
	panel(Rect2(392, 24, maxf(260, w - 672), 105))
	var mode := "AI PILOT" if game.ai else "MANUAL"
	text_at(Vector2(411, 50), mode + "  /  " + game.navigation, 14, Color("9cdfbe"))
	text_at(
		Vector2(411, 80),
		"BAT  %03d%%     HULL  %03d%%" % [roundi(game.battery), roundi(game.integrity)],
		20
	)
	text_at(
		Vector2(411, 111),
		(
			"SCORE  %04d    TIME  %02d:%02d"
			% [game.score, floori(game.elapsed / 60.0), int(game.elapsed) % 60]
		),
		15,
		muted
	)
	panel(Rect2(26, 151, 308, 272))
	text_at(Vector2(46, 179), "MISSION MANIFEST", 13, muted)
	for i in game.missions.size():
		var y: int = 213 + i * 52
		var done: bool = i < game.mission_index
		var color := Color("8adab5") if done or i == game.mission_index else muted
		text_at(
			Vector2(46, y),
			("✓  " if done else "%02d  " % (i + 1)) + str(game.missions[i].title),
			16,
			color
		)
		var p: Vector3 = game.missions[i].target
		text_at(
			Vector2(72, y + 20),
			(
				"COMPLETE"
				if done
				else (
					"%.0f m  ·  +%d pts"
					% [game.drone.position.distance_to(p), game.missions[i].points]
				)
			),
			12,
			muted
		)
	if not game.order.is_empty():
		text_at(Vector2(46, 260), "%d x %s" % [game.order.quantity, game.order.item], 16)
		text_at(Vector2(46, 290), game.order.state, 14, Color("9cdfbe"))
		text_at(Vector2(46, 319), "Recipient: Peace Gate picnic point", 12, muted)
	text_at(Vector2(46, 380), "Return and land", 16, muted)
	text_at(Vector2(46, 402), "TAB  AI / manual     H  return home", 12, Color("a6d7c1"))
	if game.phase == game.Phase.SERVICE:
		var ratio: float = game.service_time / float(game.missions[game.mission_index].seconds)
		draw_rect(Rect2(46, 431, 260, 5), Color("2a4d47"))
		draw_rect(Rect2(46, 431, 260 * ratio, 5), Color("9cdfbe"))
	if game.in_progress():
		var cam: Camera3D = game.drone.camera
		var target: Vector3 = game.target()
		if not cam.is_position_behind(target):
			var p := cam.unproject_position(target)
			if p.x > 345 and p.x < w - 260 and p.y > 145 and p.y < size.y - 150:
				draw_arc(p, 13, 0, TAU, 32, Color("9cdfbe"), 2, true)
				text_at(
					p + Vector2(18, 5),
					"TARGET  %.0f m" % game.drone.position.distance_to(target),
					13
				)
	var menu: bool = (
		game.phase
		in [game.Phase.BRIEFING, game.Phase.DOCKED, game.Phase.COMPLETE, game.Phase.FAILED]
	)
	if not menu:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, .025, .03, .30))
	var base := size * .5 - Vector2(250, 208)
	panel(Rect2(base, Vector2(500, 430)))
	text_at(base + Vector2(30, 39), "C O A S T    /    SEOUL", 16, muted)
	var title := "ORDER DRONE DELIVERY"
	if game.phase == game.Phase.COMPLETE:
		title = "SORTIE COMPLETE"
	if game.phase == game.Phase.FAILED:
		title = "MISSION ABORTED"
	if game.phase == game.Phase.DOCKED:
		title = "AIRCRAFT DOCKED"
	text_at(base + Vector2(30, 84), title, 28)
	if game.phase == game.Phase.BRIEFING:
		text_at(
			base + Vector2(30, 125), "Choose your items                     Quantity", 16, muted
		)
		text_at(base + Vector2(30, 222), "Deliver to: Peace Gate picnic point", 17)
		text_at(
			base + Vector2(30, 252), "AI flies your order there, delivers, and returns.", 15, muted
		)
		text_at(base + Vector2(30, 279), "Simulation order · no payment required", 13, muted)
	else:
		text_at(
			base + Vector2(30, 133),
			(
				"SCORE  %04d   /   TASKS  %d OF %d"
				% [game.score, game.completed_count, game.missions.size()]
			),
			23
		)
		text_at(
			base + Vector2(30, 173),
			"Battery  %.0f%%    Hull  %.0f%%" % [game.battery, game.integrity],
			18,
			muted
		)
		text_at(base + Vector2(30, 220), game.status, 14, muted)
