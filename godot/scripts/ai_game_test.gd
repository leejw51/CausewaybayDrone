extends RefCounted


func run(main: Node3D) -> void:
	var tree := main.get_tree()
	var game: Node = main.game
	var drone: CharacterBody3D = main.drone
	for i in range(3):
		await tree.physics_frame
	game.begin(true)
	for frame in range(24000):
		await tree.physics_frame
		if frame % 1800 == 0:
			print(
				(
					"AI_PROGRESS task=%d phase=%d battery=%.1f position=%s nav=%s"
					% [
						game.mission_index,
						game.phase,
						game.battery,
						str(drone.position),
						game.navigation
					]
				)
			)
		if game.phase in [game.Phase.COMPLETE, game.Phase.FAILED]:
			break
	assert(game.phase == game.Phase.COMPLETE, "AI must finish three tasks and return to base")
	assert(game.completed_count == 3 and game.score >= 1200, "Mission scoring failed")
	assert(drone.position.distance_to(game.home) < 3, "AI did not return home")
	assert(game.battery > 0 and game.integrity > 0, "AI must preserve aircraft")
	print(
		(
			"AI_CAMPAIGN_OK time=%.1f battery=%.1f hull=%.1f score=%d"
			% [game.elapsed, game.battery, game.integrity, game.score]
		)
	)
	game.restart()
	game.begin(true)
	game.take_over()
	assert(not drone.ai_enabled, "Manual takeover failed")
	game.toggle_ai()
	assert(drone.ai_enabled, "AI resume failed")
	game.battery = 19
	await tree.physics_frame
	await tree.physics_frame
	assert(game.phase == game.Phase.RETURNING, "Low-battery return failed")
	game.damage(100)
	assert(game.phase == game.Phase.FAILED, "Hull failure state missing")
	game.restart()
	assert(
		game.phase == game.Phase.BRIEFING and game.battery == 100 and game.score == 0,
		"Restart must clear sortie"
	)
	# A manual task requires a sustained interaction, not one button press.
	game.begin(false)
	drone.position = game.target()
	drone.velocity = Vector3.ZERO
	Input.action_press("interact")
	for i in range(240):
		await tree.physics_frame
	Input.action_release("interact")
	assert(game.mission_index == 1 and game.score == 300, "Manual service dwell failed")
	var kspo: Dictionary = main.park.landmark("KSPO DOME")
	var center: Vector3 = main.park.vec(kspo.position)
	drone.position = center + Vector3(-100, 20, 0)
	game.plan_route(center + Vector3(100, 2, 0))
	assert(
		game.route[1].y >= center.y + float(kspo.height) + 15,
		"Planner must clear the mapped stadium roof"
	)
	print(
		"AI_GAME_TEST_OK: campaign, scoring, return, takeover/resume, low battery, damage, restart, manual service, roof clearance"
	)
	tree.quit()
