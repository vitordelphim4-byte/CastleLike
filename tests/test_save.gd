extends SceneTree
## Run: godot --headless --path . -s tests/test_save.gd
## Save -> load round trip: same seed, dug/built blocks, cut tree, pieces, orders, blueprints,
## stock, clock, villager priorities and cargo all come back; the save list shows it; delete works.

var failed := false


func _initialize() -> void:
	var game := root.get_node("Game")
	var SaveGame = load("res://scripts/save_game.gd")  # loaded late: it needs the Game autoload
	game.world_name = "zz_test_save"
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var w = game.world
	var s := Vector3i(game.stockpile.floor())
	var top: int = w.top_at(s.x + 4, s.z + 4)
	var dug := Vector3i(s.x + 4, top - 1, s.z + 4)
	w.set_block(dug, 0)  # AIR
	var brick := Vector3i(s.x - 4, w.top_at(s.x - 4, s.z - 4), s.z - 4)
	w.set_block(brick, World.BRICK)
	var door := Vector3i(s.x + 6, w.top_at(s.x + 6, s.z), s.z)
	w.add_prop(door, "wood_door", Vector3i.FORWARD)
	var cut: Vector3i = w.trees.keys()[0]
	w.remove_tree(cut)
	game.store("wood", 7)
	game.store("stone", 3)
	game.time_of_day = 0.6
	game.day = 4
	var dig: Dictionary = game.add_order("dig", Rect2i(s.x - 8, s.z + 8, 2, 2))
	game.toggle_pause(dig)
	var bp := Vector3i(s.x - 6, w.top_at(s.x - 6, s.z + 3), s.z + 3)
	game.place_plan({bp: {"item": "stone_block", "dir": Vector3i.FORWARD}})
	var wk = get_nodes_in_group("workers")[0]
	wk.priorities = {"build": 1, "dig": 0, "wood": 4}
	wk._set_cargo("wood", 1)
	var seed_value: int = w.gen.world_seed
	var dig_cells: int = dig.cells.size()
	var wk_name: String = wk.worker_name

	_check(SaveGame.write(main), "write ok")
	var listed: Array = SaveGame.list().filter(func(h: Dictionary) -> bool: return h.name == "zz_test_save")
	_check(listed.size() == 1 and listed[0].day == 4, "save listed with day 4: %s" % [listed])

	root.remove_child(main)
	main.free()
	game.pending_load = SaveGame.read(SaveGame.path_for("zz_test_save"))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	w = game.world

	_check(w.gen.world_seed == seed_value, "same seed")
	_check(w.get_block(dug) == 0, "dug block stays dug")
	_check(w.get_block(brick) == World.BRICK, "built block stays")
	_check(w.props.has(door) and w.props[door].item == "wood_door", "door restored")
	_check(not w.trees.has(cut), "cut tree stays cut")
	_check(game.stock.wood == 7 and game.stock.stone == 3, "stock: %s" % game.stock)
	_check(game.day == 4 and absf(game.time_of_day - 0.6) < 0.01, "clock: day %d t %f" % [game.day, game.time_of_day])
	_check(game.orders.size() == 1 and game.orders[0].paused and game.orders[0].cells.size() == dig_cells,
		"dig order restored paused with its cells")
	_check(game.blueprints.has(bp), "blueprint restored")
	var wk2 = get_nodes_in_group("workers").filter(func(x) -> bool: return x.worker_name == wk_name)[0]
	_check(wk2.priorities.dig == 0 and wk2.priorities.build == 1, "priorities: %s" % wk2.priorities)
	_check(wk2.carrying == "wood", "cargo restored")

	SaveGame.delete(SaveGame.path_for("zz_test_save"))
	_check(not FileAccess.file_exists(SaveGame.path_for("zz_test_save")), "delete removes the file")
	if not failed:
		print("test_save OK")
	quit(1 if failed else 0)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		failed = true
