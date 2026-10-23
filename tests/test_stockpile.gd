extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_stockpile.gd
## Stockpile zones: per-tile capacity (one kind per tile), full stock stops woodcutting and leaves
## the carrier waiting, withdrawing frees room, shrinking/removing a zone moves goods to other
## tiles, digging skips stockpile tiles, a villager delivers onto a tile.

var failed := false


func _initialize() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	var game := root.get_node("Game")
	await process_frame
	var per: int = game.RESOURCES.wood.per_tile
	var start: Dictionary = game.zones[0]
	_check(start.tiles.size() == 9, "starting zone has 9 tiles: %d" % start.tiles.size())
	var tiles: int = start.tiles.size()

	_check(game.store("wood", per + 1) == 0 and game.zone_used(start) == 2, "11 wood use 2 tiles")
	_check(game.store("stone", 3) == 0 and game.zone_used(start) == 3, "stone takes its own tile")
	var left: int = game.store("wood", per * tiles)
	_check(game.stock.wood == per * (tiles - 1) and left > 0, "full: %d wood stored, %d left over" % [game.stock.wood, left])
	_check(not game.has_room("wood"), "no room for wood")

	var w = get_nodes_in_group("workers")[0]
	for o in get_nodes_in_group("workers"):
		for k in o.priorities:
			o.priorities[k] = 0
	game.add_order("wood", Rect2i(-48, -48, 96, 96))
	w.priorities.wood = 1
	_check(not w._find_job(), "no woodcutting with a full stock")
	w._set_cargo("wood", 1)
	await process_frame
	await process_frame
	_check(w.no_room and w.carrying == "wood", "carrier waits: %s" % w.activity())

	var full = game.withdraw_tile("wood", 3, w.position)
	_check(full != null and game.withdraw(full, "wood", 3), "withdraw 3 wood")
	for i in 600:
		await process_frame
		if w.carrying == "":
			break
	_check(w.carrying == "" and not w.no_room, "cargo delivered once there's room")

	# Second zone, then remove the first: goods move over (what fits).
	var s := Vector3i(game.stockpile.floor())
	var z2: Dictionary = game.add_zone(Rect2i(s.x + 4, s.z - 6, 3, 3))
	var total: int = game.stock.wood + game.stock.stone
	game.remove_zone(start)
	_check(game.zones.size() == 1 and game.stock.wood + game.stock.stone == mini(total, per * 8 + 16), \
		"goods moved to zone 2: %s" % game.stock)

	var tile: Vector3i = z2.tiles.keys()[0]
	var cells: Dictionary = game.dig_cells(Rect2i(tile.x, tile.z, 1, 1), 2)
	_check(cells.is_empty(), "no digging under a stockpile tile")

	if not failed:
		print("test_stockpile OK")
	quit(1 if failed else 0)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		failed = true
