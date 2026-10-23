extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_roof.gd
## Debug map houses: 5x5 gets a wooden hip roof, 10x5 a slate gable roof with overhang. Neither
## house has a way up, so each roof plan must bring its own ladder; workers then build everything
## climbing the roof as it grows. 300 simulated seconds.

var failed := false


func _initialize() -> void:
	root.add_child(load("res://debug.tscn").instantiate())
	var game := root.get_node("Game")
	var main := root.get_node("Main")
	await process_frame
	var world: World = game.world
	var small: Rect2i = main.debug_houses[0]
	var long: Rect2i = main.debug_houses[1]
	var base := world.top_at(small.position.x, small.position.y)  # right above the 3-high walls
	_check(small.size == Vector2i(5, 5) and long.size == Vector2i(10, 5), "debug houses are 5x5 and 10x5")

	game.roof_type = "hip"
	game.roof_mat = "wood"
	game.roof_overhang = false
	game.plan_roof(small, base)
	game.roof_type = "gable"
	game.roof_mat = "stone"
	game.roof_overhang = true
	game.build_rot = 0  # ridge along X, the long side
	game.plan_roof(long, base)
	var ladders: Array = game.blueprints.keys().filter(func(c: Vector3i) -> bool: return game.blueprints[c].item == "ladder")
	_check(ladders.size() >= 2 * 3, "each roof plan brought a ladder, got %d ladder cells" % ladders.size())
	var total: int = game.blueprints.size()

	for frame in 18000:
		await process_frame
		if game.blueprints.is_empty():
			break
	_check(game.blueprints.is_empty(), "roofs finished, %d of %d pieces left" % [game.blueprints.size(), total])
	if not game.blueprints.is_empty():
		for c: Vector3i in game.blueprints.keys().slice(0, 12):
			printerr("  left %s %s supported=%s" % [c, game.blueprints[c].item, game.supported(c)])
		for w in root.get_tree().get_nodes_in_group("workers"):
			printerr("  %s at %s: %s, unreachable %d" % [w.worker_name, w.position, w.activity(), w.unreachable.size()])
	var peak := Vector3i(small.position.x + 2, base + 2, small.position.y + 2)
	_check(world.props.has(peak) and world.props[peak].item == "wood_peak", "hip roof has its peak at %s" % peak)
	var ridge := Vector3i(long.position.x + 5, base + 2, long.position.y + 2)
	_check(world.props.has(ridge) and world.props[ridge].item == "stone_ridge", "gable roof has its ridge at %s" % ridge)
	var gable_fill := Vector3i(long.position.x, base + 1, long.position.y + 2)
	_check(world.get_block(gable_fill) == World.BRICK, "gable end closed with stone under the ridge")
	if not failed:
		print("test_roof OK (%d pieces)" % total)
	quit(1 if failed else 0)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		failed = true
