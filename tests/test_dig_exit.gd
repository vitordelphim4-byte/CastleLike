extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_dig_exit.gd
## On the flat debug map, a lone miner digs a 1x1 shaft 6 deep. It must finish and still be able
## to walk back to the stockpile (emergency ladders). 120 simulated seconds.


func _initialize() -> void:
	root.add_child(load("res://debug.tscn").instantiate())
	var game := root.get_node("Game")
	await process_frame
	var world: World = game.world
	if not world.flat or not game.infinite:
		_fail("debug.tscn should be flat with infinite resources")
		return
	var workers := root.get_tree().get_nodes_in_group("workers")
	var miner = workers[0]
	for w in workers:
		for work in w.priorities:
			w.priorities[work] = 0
	miner.priorities.dig = 1
	var s := Vector3i(game.stockpile.floor())
	game.dig_depth = 6
	var order: Dictionary = game.add_order("dig", Rect2i(s.x + 4, s.z + 4, 1, 1))

	for frame in 7200:
		await process_frame
		if order.cells.is_empty() and miner.path.is_empty() and miner.state == miner.IDLE:
			var out: PackedVector3Array = world.find_path(miner.position, game.stockpile)
			if out.is_empty() or out[-1].distance_to(game.stockpile) > 1.5:
				_fail("miner finished but is trapped at %s" % miner.position)
				return
			print("test_dig_exit OK (frame %d, %d ladders)" % [frame, world.props.size()])
			quit()
			return
	_fail("dig cells left: %d, miner at %s" % [order.cells.size(), miner.position])


func _fail(msg: String) -> void:
	printerr("FAIL: ", msg)
	quit(1)
