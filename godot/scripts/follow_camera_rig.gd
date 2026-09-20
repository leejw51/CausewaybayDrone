extends RefCounted
## One filtered anchor drives translation and aim; telemetry jitter cannot rotate the view.
var initialized := false
var anchor := Vector3.ZERO
var offset := Vector3.ZERO


func reset(target: Vector3, camera_offset: Vector3) -> void:
	anchor = target
	offset = camera_offset
	initialized = true


func advance(
	target: Vector3, camera_offset: Vector3, delta: float, target_is_interpolated := false
) -> Vector3:
	if not initialized:
		reset(target, camera_offset)
	var dt := maxf(delta, 0.0)
	anchor = target if target_is_interpolated else anchor.lerp(target, 1.0 - exp(-5.0 * dt))
	offset = offset.lerp(camera_offset, 1.0 - exp(-9.0 * dt))
	return anchor + offset
