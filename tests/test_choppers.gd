extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_choppers.gd
## Five villagers, one marked tree: at most MAX_CHOPPERS work it at once, each from its own side,
## and once it's down nobody stays stacked on another villager.

var failed := false


func _initialize() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	var game := root.get_node("Game")
	await process_frame
	var w = game.world
	var s := Vector3i(game.stockpile.floor())
	var target: Vector3i = w.trees.keys().filter(func(c) -> bool: return w.trees[c].kind != "bush").reduce(func(a, b):
		return a if Vector3(a).distance_to(Vector3(s)) < Vector3(b).distance_to(Vector3(s)) else b)
	game.add_order("wood", Rect2i(target.x, target.z, 1, 1))
	var workers := get_nodes_in_group("workers")
	var most := 0
	for frame in 3000:
		await process_frame
		var on_it := workers.filter(func(x) -> bool: return x.job_kind == "wood")
		most = maxi(most, on_it.size())
		if on_it.size() == 2 and on_it[0].job_spot != Vector3i(0, -1, 0) and on_it[0].job_spot == on_it[1].job_spot:
			_check(false, "two choppers share spot %s" % on_it[0].job_spot)
			break
		if not w.trees.has(target) and workers.all(func(x) -> bool: return x.state == 0 and x.path.is_empty() and x.carrying == ""):
			break
	_check(most > 0 and most <= 2, "choppers at once: %d" % most)
	_check(not w.trees.has(target), "tree cut down")
	for i in 240:  # let idle villagers step apart
		await process_frame
	for a in workers:
		for b in workers:
			if a != b and a.position.distance_to(b.position) < 0.4:
				_check(false, "%s stacked on %s" % [a.worker_name, b.worker_name])
	if not failed:
		print("test_choppers OK")
	quit(1 if failed else 0)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		failed = true
