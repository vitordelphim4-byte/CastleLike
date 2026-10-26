extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_debug_mine.gd
## Debug map Phase 9 hill: the chamber is reachable from the stockpile through the tunnel, the
## sealed cave really is sealed, the 2-floor building works with the floor view, and the debug
## panel's "dig tunnel" branch gets dug out.


func _initialize() -> void:
	root.add_child(load("res://debug.tscn").instantiate())
	var game := root.get_node("Game")
	await process_frame
	var main := root.get_node("Main")
	var world: World = game.world
	var mine: Dictionary = main.mine
	var path: PackedVector3Array = world.find_path(game.stockpile, mine.chamber)
	if path.is_empty() or path[-1].distance_to(mine.chamber) > 1.5:
		return _fail("chamber not reachable from the stockpile")
	var cave := Vector3i(-30, mine.cave_y, 10)
	var to_cave: PackedVector3Array = world.find_path(game.stockpile, Vector3(cave) + Vector3(0.5, 0, 0.5))
	var reached := not to_cave.is_empty() and to_cave[-1].distance_to(Vector3(cave)) < 1.5
	if world.is_solid(cave) or not world.is_solid(cave + Vector3i(0, 2, 0)) or reached:
		return _fail("sealed cave should be air with a stone roof and no way in")

	var panel: Node = null
	for n in main.get_children():
		if n.has_method("_dig_tunnel"):
			panel = n

	# The 2-floor building's upper floor is reachable by its ladder.
	var ty: int = main.tower.y
	var r: Rect2i = main.tower.rect
	var upstairs := Vector3(r.position.x + 1.5, ty + main.STOREY, r.end.y - 1.5)
	var up: PackedVector3Array = world.find_path(game.stockpile, upstairs)
	if up.is_empty() or up[-1].distance_to(upstairs) > 1.5:
		return _fail("tower's upper floor not reachable")

	# Picking a villager (top bar card) jumps the cut to its floor: none for one out in the open,
	# just over its head inside the hill's chamber or upstairs in the building.
	var top_bar := main.get_node("TopBar")
	var wk = root.get_tree().get_nodes_in_group("workers")[1]
	top_bar._focus(wk)
	if world.cut_y != World.SY:
		return _fail("villager in the open: cut should stay off, got %d" % world.cut_y)
	wk.position = mine.chamber
	top_bar._focus(wk)
	if world.cut_y != mine.y + 2:
		return _fail("villager in the chamber: cut %d, want %d" % [world.cut_y, mine.y + 2])
	wk.position = upstairs
	top_bar._focus(wk)
	if world.cut_y != ty + main.STOREY + 2:
		return _fail("villager upstairs: cut %d, want %d" % [world.cut_y, ty + main.STOREY + 2])
	wk.position = game.stockpile + Vector3(2, 0, 2)
	world.set_cut(World.SY)
	panel._dig_tunnel()
	var order: Dictionary = game.orders[-1]
	if order.cells.size() != 8:
		return _fail("tunnel branch should mark 4x2 blocks, got %d" % order.cells.size())
	for frame in 9000:
		await process_frame
		if order.cells.is_empty():
			print("test_debug_mine OK (frame %d)" % frame)
			quit()
			return
	for w in root.get_tree().get_nodes_in_group("workers"):
		print(w.worker_name, " ", w.position, " ", w.state, " ", w.job_kind, " ", w.job_cell, " unreach ", w.unreachable.keys())
	print(order.cells)
	_fail("branch blocks left: %d" % order.cells.size())


func _fail(msg: String) -> void:
	printerr("FAIL: ", msg)
	quit(1)
