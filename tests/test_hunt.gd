extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_hunt.gd
## Hunting: herds spawn around the colony; a hunter shoots a deer inside a hunting area, butchers
## the corpse and hauls raw meat to the stockpile; a wounded boar charges and scares a villager.

var failed := false


func _initialize() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	var game := root.get_node("Game")
	await process_frame
	var animal_script = load("res://scripts/animal.gd")
	_check(get_nodes_in_group("animals").size() > 0, "herds around the new colony: %d" % get_nodes_in_group("animals").size())
	for a in get_nodes_in_group("animals"):
		a.free()
	var main := root.get_node("Main")
	var w = game.world
	var s := Vector3i(game.stockpile.floor())
	var spot := Vector3(s.x + 12.5, w.top_at(s.x + 12, s.z), s.z + 0.5)
	var deer = animal_script.spawn(main.animals, w, "deer", spot)
	game.add_order("hunt", Rect2i(s.x - 40, s.z - 40, 80, 80))
	var workers := get_nodes_in_group("workers")
	for wk in workers:
		for k in wk.priorities:
			wk.priorities[k] = 1 if k == "hunt" else 0

	var got := false
	var died := false
	for frame in 6000:
		await process_frame
		died = died or not is_instance_valid(deer) or deer.state == animal_script.DEAD
		if game.stock.meat > 0:
			got = true
			break
	_check(died, "deer shot down")
	_check(got, "meat in the stockpile: %d" % game.stock.meat)
	_check(get_nodes_in_group("corpses").is_empty(), "corpse butchered")

	# Wounded boar charges.
	game.remove_order(game.orders[0])
	for wk in workers:
		for k in wk.priorities:
			wk.priorities[k] = 0
	var victim = workers[0]
	var boar = animal_script.spawn(main.animals, w, "boar", victim.position + Vector3(4, 0, 0))
	await process_frame
	boar.hurt(1, victim)
	var scared := false
	for frame in 600:
		await process_frame
		if victim.scared > 0:
			scared = true
			break
	_check(scared, "boar scared the villager")
	if not failed:
		print("test_hunt OK")
	quit(1 if failed else 0)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		failed = true
