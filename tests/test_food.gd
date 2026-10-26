extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_food.gd
## Food: berry bushes near the colony, gatherers pick a bush (it stays and regrows), a hungry
## villager walks to the stockpile and eats, with no food left a villager shows as starving.

var failed := false


func _initialize() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	var game := root.get_node("Game")
	await process_frame
	var w = game.world
	var workers := get_nodes_in_group("workers")
	_check(game.stock.berries == 20, "new colony starts with 20 berries: %d" % game.stock.berries)

	var home: Vector3 = game.stockpile
	var bush = null
	for c: Vector3i in w.trees:
		if w.trees[c].kind == "bush" and (bush == null or home.distance_to(Vector3(c)) < home.distance_to(Vector3(bush))):
			bush = c
	_check(bush != null and home.distance_to(Vector3(bush)) < 60, "a berry bush near the colony: %s (colony %s)" % [bush, home])
	if bush == null:
		quit(1)
		return

	# Gathering.
	for wk in workers:
		for k in wk.priorities:
			wk.priorities[k] = 1 if k == "gather" else 0
	game.add_order("gather", Rect2i(bush.x, bush.z, 1, 1))
	var got := false
	for frame in 4000:
		await process_frame
		if game.stock.berries > 20:
			got = true
			break
	_check(got, "berries picked and stored: %d" % game.stock.berries)
	_check(w.trees.has(bush) and w.trees[bush].amount == 0, "picked bush stays, empty")
	game.day += 2
	var node = w.tree_nodes.get(bush)
	_check(node != null and node.available() > 0, "bush regrows after a day")
	game.day -= 2

	# Hunger: a hungry villager eats from the stockpile.
	for wk in workers:
		for k in wk.priorities:
			wk.priorities[k] = 0
	var eater = workers[0]
	eater.food = 0.1
	var before: int = game.stock.berries
	for frame in 1500:
		await process_frame
		if eater.food > 0.8:
			break
	_check(eater.food > 0.8, "hungry villager ate: food %.2f" % eater.food)
	_check(game.stock.berries < before, "berries eaten: %d -> %d" % [before, game.stock.berries])

	# No food anywhere: starving.
	for z in game.zones:
		for c: Vector3i in z.tiles:
			if z.tiles[c].kind == "berries":
				game.withdraw(c, "berries", z.tiles[c].n)
	eater.food = 0.0
	await process_frame
	await process_frame
	_check(eater.activity().begins_with("Faminto"), "starving shows: %s" % eater.activity())

	if not failed:
		print("test_food OK")
	quit(1 if failed else 0)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		failed = true
