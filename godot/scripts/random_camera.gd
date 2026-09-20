extends RefCounted

var elapsed := 100.0
var duration := 0.0
var start := Vector3.ZERO
var destination := Vector3.ZERO
var target := Vector3.ZERO
var subject: Node3D
var previous := ""
var lift := 0.0
var rng := RandomNumberGenerator.new()


static func ease_in_out(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	return pow(2.0, 20.0 * t - 10.0) / 2.0 if t < .5 else (2.0 - pow(2.0, -20.0 * t + 10.0)) / 2.0


func reset() -> void:
	elapsed = 100.0
	duration = 0.0


func advance(sim: Node, delta: float) -> void:
	elapsed += delta
	if elapsed > duration + 5.0:
		var shots: Array[Dictionary] = []
		for group in [sim.humans, sim.cafes, sim.park.wildlife.targets, sim.vehicles]:
			for entry in group:
				var node: Node3D = entry.node
				var wide: bool = group == sim.cafes
				var category := (
					"cafe"
					if wide
					else (
						"human"
						if group == sim.humans
						else "animal" if group == sim.park.wildlife.targets else "drone"
					)
				)
				shots.append(
					{
						"id": str(node.get_instance_id()),
						"category": category,
						"front":
						wide or (category == "human" and is_instance_valid(entry.get("apartment"))),
						"node": node,
						"point": node.global_position + Vector3.UP,
						"distance": 12.0 if wide else 6.0
					}
				)
		for landmark in sim.park.data.landmarks:
			shots.append(
				{
					"id": str(landmark.name),
					"category": "landmark",
					"front": false,
					"node": null,
					"point":
					(
						sim.vec(landmark.position)
						+ Vector3.UP * float(landmark.get("height", 12.0)) * .5
					),
					"distance": maxf(55.0, float(landmark.get("size", [40.0, 40.0])[0]) * 1.3)
				}
			)
		shots = shots.filter(func(s): return s.id != previous)
		if shots.is_empty():
			return
		var categories: Array = []
		for candidate in shots:
			if not categories.has(candidate.category):
				categories.append(candidate.category)
		var category: String = categories[rng.randi_range(0, categories.size() - 1)]
		shots = shots.filter(func(s): return s.category == category)
		var shot: Dictionary = shots[rng.randi_range(0, shots.size() - 1)]
		previous = shot.id
		subject = shot.node
		target = shot.point
		start = sim.camera.global_position
		var angle := rng.randf_range(-.9, .9) if shot.front else rng.randf_range(-PI, PI)
		destination = target + Vector3(sin(angle), .4, cos(angle)) * float(shot.distance)
		destination.y = maxf(destination.y, sim.top(destination.x, destination.z) + 2.0)
		duration = clampf(start.distance_to(destination) / 20.0, 5.0, 90.0)
		lift = minf(180.0, start.distance_to(destination) * .3)
		# Raise the flight arc over sampled scene geometry before the flight starts.
		# Planning clearance avoids abrupt per-frame roof corrections.
		for step in range(1, 48):
			var fraction := step / 48.0
			var baseline := start.lerp(destination, fraction)
			var clearance: float = sim.top(baseline.x, baseline.z) + 3.0
			lift = maxf(lift, (clearance - baseline.y) / sin(PI * fraction))
		elapsed = 0.0
	var t := clampf(elapsed / maxf(duration, .01), 0.0, 1.0)
	var u := ease_in_out(t)
	var position := start.lerp(destination, u) + Vector3.UP * sin(PI * u) * lift
	position.y = maxf(position.y, sim.park.ground_height(position.x, position.z) + 1.0)
	sim.camera.global_position = position
	if is_instance_valid(subject):
		target = target.lerp(subject.global_position + Vector3.UP, 1.0 - exp(-2.0 * delta))
	if position.distance_squared_to(target) > .1:
		var desired := (
			Transform3D(Basis.IDENTITY, position).looking_at(target).basis.get_rotation_quaternion()
		)
		var current: Quaternion = sim.camera.global_basis.get_rotation_quaternion()
		sim.camera.global_basis = Basis(current.slerp(desired, 1.0 - exp(-2.5 * delta)))
