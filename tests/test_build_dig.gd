extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_build_dig.gd
## Workers dig a marked 3x3 patch (one layer) and build a 3-block wooden line, within 90 simulated seconds.


func _initialize() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	var game := root.get_node("Game")
	await process_frame
	var world: World = game.world
	var s := Vector3i(game.stockpile.floor())
	game.store("wood", 5)

	# Wall line 4 cells from the stockpile, on the ground.
	var wall: Array[Vector3i] = []
	for i in 3:
		var x := s.x - 1 + i
		wall.append(Vector3i(x, world.top_at(x, s.z - 4), s.z - 4))
	game.place_blueprints(wall)

	game.dig_depth = 1
	var order: Dictionary = game.add_order("dig", Rect2i(s.x - 1, s.z + 5, 3, 3))
	var dig: Array = order.cells.keys()

	for frame in 5400:
		await process_frame
		var built := wall.all(func(c: Vector3i) -> bool: return world.get_block(c) == World.WOOD)
		var dug := dig.all(func(c: Vector3i) -> bool: return not world.is_solid(c))
		if built and dug:
			_check(game.stock.wood == 2, "3 wood spent, got %d left" % game.stock.wood)
			print("test_build_dig OK (frame %d)" % frame)
			quit()
			return
	printerr("FAIL: blueprints left %d, dig cells left %s" % [game.blueprints.size(), order.cells])
	for c: Vector3i in order.cells:
		printerr("  cell %s: above solid=%s blocked=%s ladder_above=%s" % [c, world.is_solid(c + Vector3i.UP),
			world.blocked.has(c + Vector3i.UP), world.props.has(c + Vector3i.UP)])
	for w in root.get_tree().get_nodes_in_group("workers"):
		printerr("  worker %s at %s state %d job %s %s unreachable %s" % [w.worker_name, w.position, w.state, w.job_kind, w.job_cell, w.unreachable.keys()])
	quit(1)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		quit(1)
