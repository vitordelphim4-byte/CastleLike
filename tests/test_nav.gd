extends SceneTree
## Run: godot --headless --path . -s tests/test_nav.gd
## Nav on the flat infinite world: a target inside a ring wall is reachable over a 1-high wall,
## not over 2 or 3 high; ladders on both sides get you over 3; changes are patched incrementally.

var failed := false
var w: World
var ground := WorldGen.FLAT_TOP + 1
var center := Vector3i(10, 0, 0)


func _initialize() -> void:
	w = load("res://scripts/world.gd").new()
	w.flat = true
	root.add_child(w)
	await process_frame
	w.load_area(Vector3.ZERO, 2, false)  # data + nav, no meshes
	var start := Vector3(0.5, ground, 0.5)
	var target := Vector3(center.x + 0.5, ground, 0.5)
	if w.find_path(start, target).is_empty():
		printerr("FAIL: no nav on the flat world")
		quit(1)
		return
	_check(w.find_path(start, target)[-1] == target, "open ground reachable")

	_ring(1)
	_check(w.find_path(start, target)[-1] == target, "1-high step climbable")
	_ring(2)
	_check(w.find_path(start, target)[-1] != target, "2-high ring wall blocks")
	_ring(1)
	_check(w.find_path(start, target)[-1] == target, "wall lowered back to 1: reachable again")

	_ring(3)
	_check(w.find_path(start, target)[-1] != target, "3-high wall blocks")
	var wall_x := center.x - 2
	for y in range(ground, ground + 3):
		w.add_ladder(Vector3i(wall_x - 1, y, 0), Vector3i.RIGHT)
		w.add_ladder(Vector3i(wall_x + 1, y, 0), Vector3i.LEFT)
	var climb := w.find_path(start, target)
	_check(climb[-1] == target, "ladders on both sides let you cross the wall")
	_check(Array(climb).any(func(p: Vector3) -> bool: return p.y >= ground + 3), "path goes over the wall top")
	if not failed:
		print("test_nav OK")
	quit(1 if failed else 0)


# Square ring wall of height h at distance 2 around the target (set_block = incremental updates).
func _ring(h: int) -> void:
	for x in range(center.x - 2, center.x + 3):
		for z in range(center.z - 2, center.z + 3):
			if maxi(absi(x - center.x), absi(z - center.z)) != 2:
				continue
			for y in range(ground, ground + 3):
				var want := World.STONE if y < ground + h else World.AIR
				if w.get_block(Vector3i(x, y, z)) != want:
					w.set_block(Vector3i(x, y, z), want)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		failed = true
