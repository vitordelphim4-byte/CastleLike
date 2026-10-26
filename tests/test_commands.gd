extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_commands.gd
## Click orders: with every job switched off in the work tab, a commanded villager still chops the
## tree, digs the stone block, picks the bush, hunts (and butchers) the rabbit and harvests the ripe
## crop it was told to, then goes back to idle. Ordered while carrying, it stores the cargo first.
## The right-click picker finds animals and trees on screen; a marked animal is a hunting target
## without any hunting area.

var failed := false
var game: Node


func _initialize() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	game = root.get_node("Game")
	await process_frame
	var w = game.world
	var main := root.get_node("Main")
	for a in get_nodes_in_group("animals"):
		a.free()
	var workers := get_nodes_in_group("workers")
	for wk in workers:
		for k in wk.priorities:
			wk.priorities[k] = 0
	var wk = workers[0]
	var s := Vector3i(game.stockpile.floor())
	var y: int = w.top_at(s.x, s.z)

	# Tree.
	var tree_cell := Vector3i(s.x + 6, y, s.z + 6)
	w.add_tree({"cell": tree_cell, "kind": "oak", "size": 0, "variant": 0})
	await process_frame
	var tree = w.tree_nodes[tree_cell]
	wk._set_cargo("stone", 2)  # ordered while carrying: stores it first, then goes
	_check(wk.command("wood", tree) and wk.pending and wk.carrying == "stone", "order waits for the cargo")
	_check(await _until(func() -> bool: return game.stock.stone == 2), "cargo walked to the stockpile")
	_check(await _until(func() -> bool: return game.stock.wood > 0), "then the commanded chop: wood %d" % game.stock.wood)

	# Stone block in the ground.
	var rock := Vector3i(s.x - 5, y - 1, s.z + 5)
	w.set_block(rock, World.STONE)
	_check(wk.command("dig", rock), "dig command accepted")
	_check(await _until(func() -> bool: return game.stock.stone > 2), "commanded dig: stone %d" % game.stock.stone)

	# Bush.
	var bush_cell := Vector3i(s.x + 5, y, s.z - 5)
	w.add_tree({"cell": bush_cell, "kind": "bush", "size": 1, "variant": 0})
	await process_frame
	var berries: int = game.stock.berries
	_check(wk.command("gather", w.tree_nodes[bush_cell]), "gather command accepted")
	_check(await _until(func() -> bool: return game.stock.berries > berries), "commanded gather")

	# Rabbit: hunt, then butcher on its own.
	var animal_script = load("res://scripts/animal.gd")
	var rabbit = animal_script.spawn(main.animals, w, "rabbit", Vector3(s.x + 0.5, y, s.z + 12.5))
	await process_frame
	_check(wk.command("hunt", rabbit), "hunt command accepted")
	_check(await _until(func() -> bool: return game.stock.meat > 0, 4000), "commanded hunt ended in meat: %d" % game.stock.meat)

	# Ripe crop.
	var f: Dictionary = game.add_farm(Rect2i(s.x + 3, s.z - 9, 1, 1))
	var tile: Vector3i = f.tiles.keys()[0]
	f.tiles[tile].plant = "wheat"
	f.tiles[tile].sown = game.now() - 5.0
	_check(wk.command("harvest", tile), "harvest command accepted")
	_check(await _until(func() -> bool: return game.stock.wheat > 0), "commanded harvest: wheat %d" % game.stock.wheat)
	await _until(func() -> bool: return wk.carrying == "" and wk.job_kind == "")
	_check(not wk.forced and wk.job_kind == "", "back to normal after orders")

	# Picker and marking.
	var deer = animal_script.spawn(main.animals, w, "deer", Vector3(s.x + 2.5, y, s.z - 2.5))
	deer.set_process(false)
	await process_frame
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var input := root.get_node("Main/Input")
	var pick: Dictionary = input._pick_target(cam.unproject_position(deer.global_position + Vector3.UP * 0.4))
	_check(pick.get("kind") == "hunt" and pick.get("target") == deer, "picker finds the deer: %s" % [pick.get("kind")])
	deer.marked = true
	for other in workers:
		other.priorities.hunt = 1
	_check(await _until(func() -> bool: return workers.any(func(x) -> bool: return x.job_kind == "hunt" and x.prey == deer), 300),
		"marked deer is hunted without a hunting area")

	if not failed:
		print("test_commands OK")
	quit(1 if failed else 0)


func _until(cond: Callable, frames := 2500) -> bool:
	for i in frames:
		await process_frame
		if cond.call():
			return true
	return false


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		failed = true
