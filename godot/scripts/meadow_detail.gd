extends MultiMeshInstance3D

# CPU placement samples also remain available with Godot’s headless dummy renderer.
var ground_samples := PackedVector3Array()


# Cosmetic lawn detail in the known open Lone Tree lawn, within the mapped park.
# It adds no collision and makes no claim about individual surveyed plants.
func populate(park: Node3D, center: Vector3) -> void:
	var area := Rect2(Vector2(center.x - 36, center.z - 36), Vector2(72, 72))
	var paths: Array[Dictionary] = []
	for road in park.data.roads:
		for i in range(road.points.size() - 1):
			var a := Vector2(road.points[i][0], road.points[i][2])
			var b := Vector2(road.points[i + 1][0], road.points[i + 1][2])
			if area.intersects(Rect2(a, Vector2.ZERO).expand(b).grow(float(road.width))):
				paths.append({"a": a, "b": b, "width": float(road.width) * .5 + .3})
	var rng := RandomNumberGenerator.new()
	rng.seed = 17092026
	var transforms: Array[Transform3D] = []
	var shades: Array[Color] = []
	for attempt in 60000:
		var p := Vector2(center.x + rng.randf_range(-36, 36), center.z + rng.randf_range(-36, 36))
		if p.distance_to(Vector2(center.x, center.z)) > 36:
			continue
		var t: Dictionary = park.terrain
		var ix := int((p.x - float(t.x)) / float(t.step))
		var iz := int((p.y - float(t.z)) / float(t.step))
		var valid: bool = (
			ix >= 0
			and iz >= 0
			and ix < int(t.nx)
			and iz < int(t.nz)
			and t.colors[iz * int(t.nx) + ix] == 1
		)
		for polygon in park.wildlife.blocked:
			if Geometry2D.is_point_in_polygon(p, polygon):
				valid = false
		if not valid:
			continue
		for path in paths:
			if (
				Geometry2D.get_closest_point_to_segment(p, path.a, path.b).distance_to(p)
				< path.width
			):
				valid = false
				break
		if not valid:
			continue
		var scale := rng.randf_range(.65, 1.25)
		transforms.append(
			Transform3D(
				Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale),
				Vector3(p.x, park.ground_height(p.x, p.y) + .012, p.y)
			)
		)
		shades.append(Color("546535").lerp(Color("748247"), rng.randf()).srgb_to_linear())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for angle in [0.0, PI / 2]:
		for p in [Vector3(-.008, 0, 0), Vector3(.008, 0, 0), Vector3(.009, .10, .02)]:
			st.set_normal(Vector3.UP)
			st.add_vertex(p.rotated(Vector3.UP, angle))
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = st.commit()
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		if i % 137 == 0:
			ground_samples.append(transforms[i].origin)
		multimesh.set_instance_color(i, shades[i])
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/meadow.gdshader")
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	print("MEADOW_DETAIL_READY: ", transforms.size(), " lawn tufts")
