extends Control

var drone: CharacterBody3D
var park: Node3D
var mini_roads: Array[PackedVector2Array] = []
var mini_water: Array[PackedVector2Array] = []
var delivered := false
var rescued := false
var message := "Click the view to take control"
var font: Font = ThemeDB.fallback_font
var ink := Color("e9f0e9")
var muted := Color("9cb8b4")
var accent := Color("a9d8b7")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for road in park.data.roads:
		var points := PackedVector2Array()
		for i in range(0, road.points.size(), 5):
			var p: Array = road.points[i]
			points.append(map_point(Vector3(p[0], 0, p[2])))
		if points.size() > 1:
			mini_roads.append(points)
	for water in park.data.water:
		for ring in water.rings:
			var points := PackedVector2Array()
			for p in ring:
				points.append(map_point(Vector3(p[0], 0, p[1])))
			mini_water.append(points)


func map_point(p: Vector3) -> Vector2:
	var bounds: Rect2 = park.source_bounds
	return (Vector2(p.x, p.z) - bounds.position) / bounds.size * Vector2(190, 168)


func _process(_delta: float) -> void:
	queue_redraw()


func text_at(p: Vector2, txt: String, font_size := 16, color := Color("e9f0e9")) -> void:
	draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func panel(rect: Rect2) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.025, .075, .085, .9)
	style.set_corner_radius_all(12)
	style.border_color = Color(.5, .75, .69, .25)
	style.set_border_width_all(1)
	draw_style_box(style, rect)


func _draw() -> void:
	if not is_instance_valid(drone):
		return
	var w := size.x
	var h := size.y
	# Screen-space landmark names remain legible at normal flight distances.
	var used: Array[Rect2] = []
	var cam: Camera3D = drone.camera
	for item in park.landmarks:
		var center: Vector3 = park.vec(item.position)
		var world: Vector3 = center + Vector3.UP * (float(item.height) + 8)
		if cam.is_position_behind(world) or drone.position.distance_to(center) > 3000:
			continue
		var point := cam.unproject_position(world)
		if point.x < 330 or point.x > w - 270 or point.y < 140 or point.y > h - 150:
			continue
		var label_width := font.get_string_size(item.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 18
		var rect := Rect2(point - Vector2(label_width / 2, 18), Vector2(label_width, 25))
		for previous in used:
			if rect.intersects(previous.grow(4)):
				rect.position.y = previous.position.y - 30
		used.append(rect)
		draw_line(point, rect.get_center(), Color(.8, .9, .88, .6), 1)
		panel(rect)
		text_at(rect.position + Vector2(9, 17), item.name, 13)
	panel(Rect2(26, 24, 350, 105))
	draw_circle(Vector2(49, 51), 5, accent)
	text_at(Vector2(64, 57), "C O A S T    /    FLIGHT LAB", 18)
	text_at(Vector2(46, 89), "SEOUL  ·  OLYMPIC PARK", 24)
	text_at(Vector2(46, 113), "WGS84  /  1 UNIT = 1 METRE  /  TRUE NORTH", 12, muted)
	panel(Rect2(w - 252, 24, 226, 105))
	text_at(Vector2(w - 232, 51), "AIRCRAFT TELEMETRY", 12, muted)
	text_at(
		Vector2(w - 232, 84),
		"%04.1f" % (drone.position.y - park.ground_height(drone.position.x, drone.position.z)),
		29
	)
	text_at(Vector2(w - 132, 84), "m AGL", 12, muted)
	text_at(
		Vector2(w - 232, 111),
		(
			"%04.1f m/s    •    %03d°"
			% [drone.velocity.length(), posmod(-int(rad_to_deg(drone.yaw)), 360)]
		),
		15,
		accent
	)
	panel(Rect2(26, 151, 286, 175))
	text_at(Vector2(46, 179), "SIMULATED FIELD OPERATIONS", 12, muted)
	draw_line(Vector2(46, 193), Vector2(290, 193), Color(.5, .7, .65, .25))
	text_at(Vector2(46, 219), "01   COFFEE + SANDWICH", 16, accent if delivered else ink)
	text_at(
		Vector2(46, 242),
		(
			"DELIVERED"
			if delivered
			else "Delivery waypoint  /  %.0f m" % drone.position.distance_to(park.delivery_point)
		),
		13,
		muted
	)
	text_at(Vector2(46, 273), "02   LAKESIDE RESCUE", 16, accent if rescued else ink)
	text_at(
		Vector2(46, 297),
		(
			"FLOTATION DEPLOYED"
			if rescued
			else "Rescue waypoint  /  %.0f m" % drone.position.distance_to(park.rescue_point)
		),
		13,
		muted
	)
	# Compact live map: north is -Z and the marker follows the aircraft.
	var origin := Vector2(w - 134, h - 194)
	panel(Rect2(w - 252, h - 326, 226, 244))
	text_at(Vector2(w - 232, h - 300), "PARK NAVIGATION      N ↑", 12, muted)
	draw_rect(Rect2(origin - Vector2(95, 88), Vector2(190, 168)), Color("354f42"))
	var offset := origin - Vector2(95, 88)
	draw_set_transform(offset)
	for polygon in mini_water:
		draw_colored_polygon(polygon, Color("437d7b"))
	for path in mini_roads:
		draw_polyline(path, Color(.65, .70, .63, .6), .7, true)
	draw_set_transform(Vector2.ZERO)
	for item in park.landmarks:
		var point := offset + map_point(park.vec(item.position))
		draw_rect(Rect2(point - Vector2(2, 2), Vector2(4, 4)), Color("b5d5e0"))
	var player := offset + map_point(drone.position)
	player.x = clampf(player.x, origin.x - 91, origin.x + 91)
	player.y = clampf(player.y, origin.y - 82, origin.y + 82)
	draw_circle(player, 5, Color("ffe0a2"))
	var nose := Vector2(-sin(drone.yaw), -cos(drone.yaw))
	draw_line(player, player + nose * 12, Color("ffe0a2"), 2)
	text_at(Vector2(w - 232, h - 101), "OSM GEOMETRY  /  NORTH UP", 10, muted)
	var geo: Dictionary = park.data.origin
	text_at(
		Vector2(28, h - 73),
		(
			"© OpenStreetMap contributors · ODbL  |  Terrain: Mapzen / USGS  |  %.5f° N  %.5f° E"
			% [
				float(geo.lat) - drone.position.z / float(geo.metres_per_lat_degree),
				float(geo.lon) + drone.position.x / float(geo.metres_per_lon_degree)
			]
		),
		11,
		ink
	)
	panel(Rect2(26, h - 136, 620, 54))
	text_at(Vector2(46, h - 103), message, 16, accent)
	panel(Rect2(26, h - 66, w - 52, 42))
	text_at(
		Vector2(45, h - 39),
		"WASD  move    SPACE / CTRL  altitude    SHIFT  boost    MOUSE  look    WHEEL  zoom    F  service    TAB  AI    H  home    R  restart    ESC  cursor",
		14
	)
	# Minimal center sight.
	draw_circle(size * .5, 2, Color(1, 1, 1, .7))
