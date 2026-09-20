extends Node3D
# GPU effects visualize rotor wash and servicing. They do not apply flight forces.
var sim: Node3D
var fleet: Array[Dictionary] = []
var run_id := ""
var ground_timer := 0.0


func emitter(
	tint: Color,
	amount: int,
	life: float,
	direction: Vector3,
	speed: float,
	radius: float,
	size: float
) -> GPUParticles3D:
	var fx := GPUParticles3D.new()
	fx.emitting = false
	fx.amount = amount
	fx.lifetime = life
	fx.local_coords = false
	fx.visibility_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))
	var process := ParticleProcessMaterial.new()
	process.direction = direction
	process.spread = 35.0
	process.gravity = Vector3(0, -.5, 0)
	process.initial_velocity_min = speed * .5
	process.initial_velocity_max = speed
	process.scale_min = .5
	process.scale_max = 1.5
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, .15, 1.0])
	fade.colors = PackedColorArray([Color(tint, 0.0), tint, Color(tint, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	fx.process_material = process
	var soft := Gradient.new()
	soft.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = soft
	texture.width = 32
	texture.height = 32
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(.5, .5)
	texture.fill_to = Vector2(1, .5)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.no_depth_test = false
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.material = material
	fx.draw_pass_1 = quad
	add_child(fx)
	return fx


func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	fleet.clear()
	run_id = sim.built_run
	for drone in sim.vehicles:
		var wash := emitter(Color(.76, .89, 1, .20), 28, .45, Vector3.DOWN, 5, .85, .10)
		var dust := emitter(Color(.76, .68, .51, .32), 36, 1.2, Vector3.UP, 1.8, 1.4, .65)
		var charge := emitter(Color(.16, 1, .72, .85), 16, .7, Vector3.UP, 1.5, .15, .14)
		var sparks := emitter(Color(1, .65, .17, 1), 32, .55, Vector3.UP, 3.2, .08, .14)
		var burst := emitter(Color(.28, 1, .83, .9), 24, .75, Vector3.UP, 2.2, .25, .13)
		burst.one_shot = true
		burst.explosiveness = 1.0
		fleet.append(
			{
				"wash": wash,
				"dust": dust,
				"charge": charge,
				"sparks": sparks,
				"burst": burst,
				"last_state": drone.state,
				"ground": drone.node.position.y - 2
			}
		)


func _process(delta: float) -> void:
	if sim.vehicles.is_empty() or not is_instance_valid(sim.world):
		return
	if run_id != sim.built_run or fleet.size() != sim.vehicles.size():
		rebuild()
	ground_timer += delta
	var refresh_ground := ground_timer > .3
	if refresh_ground:
		ground_timer = 0.0
	for i in fleet.size():
		var fx: Dictionary = fleet[i]
		var drone: Dictionary = sim.vehicles[i]
		var p: Vector3 = drone.node.global_position
		var nearby: bool = sim.camera.global_position.distance_to(p) < 70
		var active: bool = sim.running and sim.transport.connected() and not sim.ui.title_visible
		var airborne: bool = drone.state not in ["IDLE", "CHARGING", "DIAGNOSING", "REPAIRING"]
		if refresh_ground and nearby:
			fx.ground = sim.top(p.x, p.z)
		fx.wash.global_position = p - Vector3.UP * .5
		fx.dust.global_position = Vector3(p.x, float(fx.ground) + .1, p.z)
		fx.charge.global_position = sim.docks[i].node.global_position + Vector3(1.2, -.5, 0)
		fx.sparks.global_position = sim.docks[i].arm.to_global(Vector3(1.2, .8, 0))
		fx.burst.global_position = p - Vector3.UP * .8
		fx.wash.emitting = (
			active and airborne and nearby and sim.camera.global_position.distance_to(p) < 35
		)
		fx.dust.emitting = (
			active and airborne and nearby and p.y - float(fx.ground) < 6 and p.y > float(fx.ground)
		)
		fx.charge.emitting = active and nearby and drone.state == "CHARGING"
		fx.sparks.emitting = (
			active
			and nearby
			and drone.state == "REPAIRING"
			and drone.get("maintenance", {}).get("elapsed", 0.0) > 20
		)
		if fx.last_state != drone.state:
			if active and nearby and drone.state in ["UNLOADING", "RETURNING"]:
				fx.burst.restart()
			fx.last_state = drone.state
		for key in ["wash", "dust", "charge", "sparks", "burst"]:
			fx[key].speed_scale = 1.0 if active else 0.0
			fx[key].visible = (
				nearby
				and not (sim.first_person and sim.focus_kind == "drone" and sim.focus_index == i)
			)
