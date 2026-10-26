extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_farm.gd
## Farming: a growing zone gets sown (soil turns to farmland), crops ripen with time, farmers
## harvest them into the stockpile; a hungry villager eats carrots when there are no berries;
## farms survive a save round trip.

var failed := false


func _initialize() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	var game := root.get_node("Game")
	await process_frame
	var w = game.world
	var s := Vector3i(game.stockpile.floor())
	var f: Dictionary = game.add_farm(Rect2i(s.x + 3, s.z + 3, 3, 2))
	_check(f.tiles.size() == 6, "farm has 6 tiles: %d" % f.tiles.size())
	game.cycle_crop(f)
	_check(f.crop == "carrot", "crop switched to carrot: %s" % f.crop)
	var workers := get_nodes_in_group("workers")
	for wk in workers:
		for k in wk.priorities:
			wk.priorities[k] = 1 if k == "farm" else 0

	var sown := false
	for frame in 3000:
		await process_frame
		if f.tiles.values().all(func(t) -> bool: return t.plant == "carrot"):
			sown = true
			break
	_check(sown, "all tiles sown")
	var tile: Vector3i = f.tiles.keys()[0]
	_check(w.get_block(tile + Vector3i.DOWN) == World.FARMLAND, "soil became farmland")
	_check(game.farm_ripe(f) == 0, "nothing ripe right after sowing")

	game.day += 2  # let it grow
	var harvested := false
	for frame in 3000:
		await process_frame
		if game.stock.carrot >= 6 * 4:  # 6 tiles x 4 carrots
			harvested = true
			break
	_check(harvested, "carrots harvested: %d" % game.stock.carrot)

	# Hungry, no berries: eats carrots.
	for z in game.zones:
		for c: Vector3i in z.tiles:
			if z.tiles[c].kind == "berries":
				game.withdraw(c, "berries", z.tiles[c].n)
	for wk in workers:
		for k in wk.priorities:
			wk.priorities[k] = 0
	var eater = workers[1]
	eater.food = 0.1
	var carrots: int = game.stock.carrot
	for frame in 1500:
		await process_frame
		if eater.food > 0.8:
			break
	_check(eater.food > 0.8 and game.stock.carrot < carrots, "ate carrots: food %.2f, carrots %d -> %d" % [eater.food, carrots, game.stock.carrot])

	var data: Dictionary = load("res://scripts/save_game.gd").capture(root.get_node("Main"))
	_check(data.farms.size() == 1 and data.farms[0].crop == "carrot" and data.farms[0].tiles.size() == 6, "farm saved")
	if not failed:
		print("test_farm OK")
	quit(1 if failed else 0)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		failed = true
