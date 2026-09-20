extends RefCounted


func run(main: Node3D) -> void:
	var tree := main.get_tree()
	var game: Node = main.game
	for i in range(3):
		await tree.physics_frame
	assert(not game.place_order(-1, 1))
	assert(not game.place_order(0, 4))
	var ui: Control = main.get_node("CanvasLayer/GameUI")
	ui.product.select(2)
	ui.quantity.value = 2
	ui.primary.pressed.emit()
	assert(game.order.item == "Sandwich + Coffee" and game.order.quantity == 2)
	assert(game.ai and game.missions.size() == 1)
	assert(not game.place_order(0, 1), "Busy aircraft must reject duplicate orders")
	for frame in range(12000):
		await tree.physics_frame
		if game.phase in [game.Phase.COMPLETE, game.Phase.FAILED]:
			break
	assert(game.phase == game.Phase.COMPLETE, "Order must arrive and drone return")
	assert(game.order.state == "DELIVERED" and game.completed_count == 1)
	assert(game.score >= 600 and main.drone.position.distance_to(game.home) < 3)
	ui.primary.pressed.emit()
	assert(game.phase == game.Phase.BRIEFING and game.order.is_empty())
	assert(game.missions.size() == 3, "Training campaign must survive order reset")
	assert(game.place_order(1, 1))
	assert(game.order.id == 2 and game.order.item == "Coffee")
	game.fail("Test failure")
	assert(game.order.state == "DELIVERY FAILED")
	print(
		"ORDER_TEST_OK: menu submission, payload, duplicate protection, autonomous delivery, return, new order, failure"
	)
	tree.quit()
