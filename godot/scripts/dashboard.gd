extends Control

var sim: Node
var cards: GridContainer
var sections: GridContainer
var values: Array[Label] = []
var fleet: VBoxContainer
var shops: VBoxContainer
var recent: VBoxContainer
var chart: Control
var status: Label
var toggle: Button
var refresh := 0.0
var bars: Array[int] = []
var fleet_rows: Array[Dictionary] = []
var shop_rows: Array[Label] = []
var order_rows: Array[Label] = []
var summary: Dictionary = {}
var transition: Tween


func text(parent: Node, value: String, font_size := 16) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func panel(parent: Node, title: String) -> VBoxContainer:
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("163540")
	style.border_color = Color("408b92")
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	for edge in ["left", "right", "top", "bottom"]:
		style.set("content_margin_" + edge, 16.0)
	box.add_theme_stylebox_override("panel", style)
	parent.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	box.add_child(column)
	text(column, title, 18).modulate = Color("ffcf78")
	return column


func list_area(parent: Node) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 240
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	return column


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 30
	var background := ColorRect.new()
	background.color = Color(.015, .04, .055, .97)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)
	var header := HFlowContainer.new()
	root.add_child(header)
	var heading := text(header, "Dashboard", 28)
	heading.modulate = Color("79e5cd")
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	sim.ui.button(header, "Close  ×", close)
	toggle = sim.ui.button(
		header, "Pause", func(): sim.send({"command": "stop" if sim.running else "start"})
	)
	sim.ui.button(
		header,
		"Orders",
		func():
			close()
			sim.ui.open_page(1)
	)
	status = text(root, "", 14)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	scroll.add_child(content)
	cards = GridContainer.new()
	cards.columns = 3
	cards.add_theme_constant_override("h_separation", 12)
	cards.add_theme_constant_override("v_separation", 12)
	content.add_child(cards)
	for title in [
		"Delivered",
		"Pending orders",
		"Fleet working",
		"Average battery",
		"Mean delivery time",
		"Needs attention"
	]:
		values.append(text(panel(cards, title), "—", 28))
	var activity := panel(content, "Deliveries / last 60 simulation seconds")
	chart = Control.new()
	chart.custom_minimum_size.y = 130
	activity.add_child(chart)
	text(activity, "Each bar: 5 simulation seconds / oldest to newest", 12)
	chart.draw.connect(draw_chart)
	sections = GridContainer.new()
	sections.columns = 2
	sections.add_theme_constant_override("h_separation", 16)
	sections.add_theme_constant_override("v_separation", 16)
	content.add_child(sections)
	fleet = list_area(panel(sections, "Fleet / click a drone to follow"))
	shops = list_area(panel(sections, "Robot kitchens"))
	recent = list_area(panel(content, "Recent orders"))
	visible = false


func open() -> void:
	sim.ui.set_menu_visible(false)
	sim.ui.menu_open = true
	show()
	modulate.a = 0.0
	if transition:
		transition.kill()
	transition = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	transition.tween_property(self, "modulate:a", 1.0, .25)
	refresh_data()


func close() -> void:
	sim.ui.menu_open = false
	if transition:
		transition.kill()
	hide()


func _input(event: InputEvent) -> void:
	if (
		visible
		and event is InputEventKey
		and event.pressed
		and event.physical_keycode in [KEY_ESCAPE, KEY_M]
	):
		close()
		get_viewport().set_input_as_handled()


static func aggregate(state: Dictionary) -> Dictionary:
	var result := {
		"delivered": 0,
		"pending": 0,
		"working": 0,
		"battery": 0.0,
		"mean": 0.0,
		"alerts": 0,
		"bins": []
	}
	result.bins.resize(12)
	result.bins.fill(0)
	var now: float = state.get("time", 0.0)
	for order in state.get("orders", []):
		if order.state == "DELIVERED":
			result.delivered += 1
			result.mean += maxf(0.0, float(order.delivered) - float(order.created))
			var age := now - float(order.delivered)
			if age >= 0.0 and age < 60.0:
				result.bins[11 - int(age / 5.0)] += 1
		elif order.state != "FAILED":
			result.pending += 1
	for drone in state.get("vehicles", []):
		result.battery += float(drone.battery)
		if drone.state not in ["IDLE", "CHARGING", "DIAGNOSING", "REPAIRING"]:
			result.working += 1
		if drone.battery < 25 or drone.get("maintenance", {}).get("health", 100) < 85:
			result.alerts += 1
	result.battery /= maxf(1, state.get("vehicles", []).size())
	result.mean /= maxf(1, result.delivered)
	return result


func refresh_data() -> void:
	summary = aggregate(sim.state)
	values[0].text = str(summary.delivered)
	values[1].text = str(summary.pending)
	values[2].text = "%d / %d" % [summary.working, sim.vehicles.size()]
	values[3].text = "%.0f%%" % summary.battery if not sim.vehicles.is_empty() else "—"
	values[4].text = tr("%.1f s") % summary.mean if summary.delivered else "—"
	values[5].text = str(summary.alerts)
	values[5].modulate = Color("ffbe76") if summary.alerts else Color("79e5cd")
	bars.assign(summary.bins)
	chart.queue_redraw()
	toggle.text = tr("Pause") if sim.running else tr("Start")
	status.text = (
		(tr("RUNNING") if sim.running else tr("STOPPED"))
		+ "  ·  "
		+ (
			tr("Live connection")
			if sim.transport.connected()
			else tr("Connection lost / last received data")
		)
	)
	while fleet_rows.size() != sim.vehicles.size():
		for row in fleet_rows:
			row.root.queue_free()
		fleet_rows.clear()
		for i in sim.vehicles.size():
			var row := VBoxContainer.new()
			fleet.add_child(row)
			var watch: Button = sim.ui.button(
				row,
				"",
				func():
					close()
					sim.set_free_camera(false)
					sim.director = false
					sim.first_person = false
					sim.focus_kind = "drone"
					sim.focus_index = i
					sim.ui.drone_list.select(i)
					sim.zoom = 12
			)
			var gauge := ProgressBar.new()
			gauge.custom_minimum_size.y = 18
			var fill := StyleBoxFlat.new()
			fill.bg_color = Color("69d8bb")
			gauge.add_theme_stylebox_override("fill", fill)
			row.add_child(gauge)
			fleet_rows.append({"root": row, "button": watch, "battery": gauge})
	for i in fleet_rows.size():
		var drone: Dictionary = sim.state.vehicles[i]
		fleet_rows[i].button.text = tr("DRONE %02d") % (i + 1) + " · " + tr(drone.state)
		fleet_rows[i].battery.value = drone.battery
	if shop_rows.size() != sim.cafes.size():
		for row in shop_rows:
			row.queue_free()
		shop_rows.clear()
		for i in sim.cafes.size():
			shop_rows.append(text(shops, ""))
	for i in shop_rows.size():
		var queued := 0
		for order in sim.orders:
			if int(order.cafe) == i and order.state == "ORDERED":
				queued += 1
		var job: int = sim.cafes[i].job
		var phase: String = sim.orders[job].state if job >= 0 else "READY"
		shop_rows[i].text = (
			sim.shop_name(i) + "\n" + tr(phase) + " · " + tr("Queue: %d") % queued + "\n"
		)
	while order_rows.size() < mini(20, sim.orders.size()):
		order_rows.append(text(recent, ""))
	for i in order_rows.size():
		order_rows[i].visible = i < sim.orders.size()
		if i < sim.orders.size():
			var order: Dictionary = sim.orders[sim.orders.size() - 1 - i]
			order_rows[i].text = (
				"#%03d · %s · %s × %d · %s"
				% [
					order.id,
					sim.customer_name(order.human),
					tr(order.item),
					order.quantity,
					tr(order.state)
				]
			)


func _process(delta: float) -> void:
	if not visible:
		return
	cards.columns = 3 if size.x >= 900 else 2 if size.x >= 500 else 1
	sections.columns = 2 if size.x >= 900 else 1
	refresh += delta
	if refresh >= .25:
		refresh = 0.0
		refresh_data()


func draw_chart() -> void:
	var peak := 1
	for count in bars:
		peak = maxi(peak, count)
	var width := chart.size.x / 12.0
	for i in bars.size():
		var height := 88.0 * bars[i] / peak
		chart.draw_rect(
			Rect2(i * width + 3, 98 - height, maxf(1, width - 6), maxf(2, height)), Color("79e5cd")
		)
		chart.draw_string(
			sim.ui.theme.default_font,
			Vector2(i * width + 4, 114),
			str(bars[i]),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			Color("ffcf78")
		)
