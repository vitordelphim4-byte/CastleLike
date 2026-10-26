extends SceneTree
## Run: godot --headless --path . -s tests/test_priorities.gd
## RimWorld job choice: lower priority number first, disabled works never, paused orders ignored,
## editing an order's area changes what gets dug.

var failed := false


func _initialize() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	var game := root.get_node("Game")
	await process_frame
	var s := Vector3i(game.stockpile.floor())
	game.add_order("wood", Rect2i(s.x - 32, s.z - 32, 64, 64))
	var dig: Dictionary = game.add_order("dig", Rect2i(s.x - 1, s.z + 5, 3, 3))
	var w = root.get_tree().get_nodes_in_group("workers")[0]  # untyped: Worker can't compile before autoloads in -s mode

	w.priorities = {"build": 0, "dig": 2, "wood": 1}
	_check(w._find_job() and w.job_kind == "wood", "priority 1 (wood) beats 2 (dig): got '%s'" % w.job_kind)
	w._drop_job()

	w.priorities = {"build": 0, "dig": 1, "wood": 1}
	_check(w._find_job() and w.job_kind == "dig", "tie: column order puts dig before wood: got '%s'" % w.job_kind)
	w._drop_job()

	w.priorities = {"build": 0, "dig": 0, "wood": 2}
	_check(w._find_job() and w.job_kind == "wood", "disabled dig is skipped: got '%s'" % w.job_kind)
	w._drop_job()

	w.priorities = {"build": 0, "dig": 1, "wood": 0}
	game.toggle_pause(dig)
	_check(not w._find_job(), "paused dig order gives no job: got '%s'" % w.job_kind)
	game.toggle_pause(dig)

	var far := Rect2i(s.x - 1, s.z - 9, 2, 2)
	game.dig_depth = 1
	game.set_order_area(dig, far)
	_check(w._find_job() and far.has_point(Vector2i(w.job_cell.x, w.job_cell.z)), "edited area is dug: cell %s" % w.job_cell)

	if not failed:
		print("test_priorities OK")
	quit(1 if failed else 0)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		failed = true
