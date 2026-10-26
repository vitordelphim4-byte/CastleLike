extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_crafting.gd
## Crafting chain: kiln turns wood into charcoal (bill "until 3"), furnace turns iron ore +
## charcoal into iron bars (bill "forever"), villagers with only Crafting enabled fetch, work and
## haul. Also: the world generator makes iron ore, an interrupted crafter walks the ingredients back,
## a demolished station leaves Game.stations.

var failed := false


func _initialize() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	var game := root.get_node("Game")
	await process_frame
	var w = game.world

	var ore := 0
	for cx in range(-6, 7, 2):
		for cz in range(-6, 7, 2):
			ore += Array(w.gen.generate(cx, cz, 16, World.SY).blocks).count(World.IRON_ORE)
	_check(ore > 0, "world has iron ore: %d blocks" % ore)

	var s := Vector3i(game.stockpile.floor())
	var kiln := Vector3i(s.x + 4, w.top_at(s.x + 4, s.z), s.z)
	var furnace := Vector3i(s.x - 6, w.top_at(s.x - 6, s.z), s.z)
	w.add_prop(kiln, "kiln", Vector3i.FORWARD)
	w.add_prop(furnace, "furnace", Vector3i.FORWARD)
	game.store("wood", 6)
	game.store("iron_ore", 2)
	var k: Dictionary = game.station(kiln)
	var f: Dictionary = game.station(furnace)
	_check(k.bills.has("charcoal") and f.bills.has("iron_bar"), "stations get their recipes")
	k.bills.charcoal.mode = "until"
	k.bills.charcoal.target = 3
	f.bills.iron_bar.mode = "forever"
	for wk in get_nodes_in_group("workers"):
		for work in wk.priorities:
			wk.priorities[work] = 1 if work == "craft" else 0

	var done := false
	for frame in 9000:
		await process_frame
		if game.stock.iron >= 2 and get_nodes_in_group("workers").all(func(x) -> bool: return x.carrying == ""):
			done = true
			break
	_check(done, "iron bars made: stock %s" % game.stock)
	_check(game.stock.iron_ore == 0, "ore used up: %d" % game.stock.iron_ore)
	_check(game.stock.wood <= 3, "wood burnt into charcoal: %d left" % game.stock.wood)

	# Interrupted with ingredients in hand: walks them back, nothing appears in the stockpile by itself.
	for wk in get_nodes_in_group("workers"):
		for work in wk.priorities:
			wk.priorities[work] = 0
	var crafter = get_nodes_in_group("workers")[0]
	await process_frame
	var ore_before: int = game.stock.iron_ore
	crafter.job_kind = "craft"
	crafter.job_cell = furnace
	crafter.held = {"iron_ore": 2}
	crafter._drop_job()
	_check(crafter.returns == {"iron_ore": 2} and game.stock.iron_ore == ore_before, "ingredients still in hand, not teleported")
	var back := false
	for frame in 1500:
		await process_frame
		if game.stock.iron_ore == ore_before + 2:
			back = true
			break
	_check(back and crafter.returns.is_empty() and crafter.carrying == "", "ingredients walked back to the stockpile")

	w.remove_prop(kiln)
	_check(game.station(kiln).is_empty() and not game.stations.has(kiln), "demolished kiln leaves the station list")
	if not failed:
		print("test_crafting OK")
	quit(1 if failed else 0)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		failed = true
