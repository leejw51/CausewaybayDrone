extends RefCounted
## Small presentation-only delay: render between received poses, never chase packet edges.
const DELAY := .15
var samples: Array[Dictionary] = []
var source_time := -INF
var last_received := -INF
var clock_offset := 0.0
var desired_offset := 0.0
var clock_samples: Array[float] = []
var last_frame := -INF
var playback_time := -INF
var underruns := 0
var frames := 0
var has_displayed := false
var displayed := Transform3D.IDENTITY
var correction_from := Transform3D.IDENTITY
var correction_started := -INF


func push(stamp: float, received_at: float, position: Vector3, attitude: Quaternion) -> void:
	if stamp <= source_time:
		return
	if (
		samples.is_empty()
		or received_at - last_received > .5
		or received_at - last_received - (stamp - source_time) > .15
	):
		if has_displayed:
			correction_from = displayed
			correction_started = received_at
		samples.clear()
		clock_offset = received_at - stamp
		desired_offset = clock_offset
		clock_samples.clear()
		last_frame = received_at
		playback_time = stamp - DELAY
	# Use sender time so ordinary network arrival jitter cannot modulate cruise speed.
	clock_samples.append(received_at - stamp)
	while clock_samples.size() > 20:
		clock_samples.pop_front()
	# A sliding low-delay estimate rejects late packets while tracking sustained clock drift.
	desired_offset = clock_samples.min()
	var timeline := stamp
	source_time = stamp
	last_received = received_at
	samples.append({"time": timeline, "position": position, "attitude": attitude.normalized()})
	while samples.size() > 16:
		samples.pop_front()


func sample(now: float) -> Transform3D:
	assert(not samples.is_empty())
	var dt := maxf(0.0, now - last_frame)
	last_frame = now
	# Slew clock correction across rendered frames, never jump when a packet arrives.
	clock_offset = lerpf(clock_offset, desired_offset, 1.0 - exp(-2.0 * dt))
	var at := maxf(playback_time, now - clock_offset - DELAY)
	playback_time = at
	frames += 1
	if samples.size() > 1 and at > float(samples[-1].time) + .001:
		underruns += 1
	while samples.size() > 2 and float(samples[1].time) <= at:
		samples.pop_front()
	var a: Dictionary = samples[0]
	if samples.size() == 1:
		return reconcile(Transform3D(Basis(a.attitude), a.position), now)
	var b: Dictionary = samples[1]
	var fraction := clampf((at - float(a.time)) / (float(b.time) - float(a.time)), 0, 1)
	var position: Vector3 = a.position.lerp(b.position, fraction)
	return reconcile(Transform3D(Basis(a.attitude.slerp(b.attitude, fraction)), position), now)


func reconcile(pose: Transform3D, now: float) -> Transform3D:
	var amount := clampf((now - correction_started) / .3, 0.0, 1.0)
	if amount < 1.0:
		amount = amount * amount * (3.0 - 2.0 * amount)
		pose = correction_from.interpolate_with(pose, amount)
	displayed = pose
	has_displayed = true
	return pose
