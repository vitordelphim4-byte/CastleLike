extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_pieces.gd
## Debug map: workers build one of every catalog piece in a row, then demolish them all and haul
## the refunds to the stockpile. Also checks slabs are stood on half a block up. 180 simulated s.

var failed := false


func _initialize() -> void:
	root.add_child(load("res://debug.tscn").instantiate())
	var game := root.get_node("Game")
	await process_frame
	var world: World = game.world
	var s := Vector3i(game.stockpile.floor())
	var y := world.top_at(s.x, s.z)
	var cells := {}  # cell -> item, every other column so pieces don't touch
	var x := s.x - 10
	for item: String in Pieces.ITEMS:
		if item == "ladder":
			continue  # needs a wall; covered by test_ladder
		cells[Vector3i(x, y, s.z - 4)] = item
		x += 2
	for c: Vector3i in cells:
		game.build_item = cells[c]
		game.place_blueprints([c] as Array[Vector3i])
	_check(game.blueprints.size() == cells.size(), "all %d pieces planned, got %d" % [cells.size(), game.blueprints.size()])

	if not await _wait(func() -> bool: return game.blueprints.is_empty(), 6000):
		_fail("still planned: %s" % [game.blueprints.keys()])
		return
	for c: Vector3i in cells:
		var item: String = cells[c]
		var built: bool = world.get_block(c) == Pieces.block_type(item) if Pieces.is_block(item) \
			else world.props.has(c) and world.props[c].item == item
		_check(built, "%s built at %s" % [item, c])
	var slab := Vector3i(s.x - 8, y, s.z - 4)
	_check(cells[slab] == "wood_slab" and is_equal_approx(world.astar.get_point_position(world.idx(slab)).y, y + 0.5),
		"stand on a slab half a block up")

	var wood_before: int = game.stock.wood
	game.build_tool = "demolish"
	game.mark_demolish(Array(cells.keys(), TYPE_VECTOR3I, "", null), true)
	_check(game.demolish.size() == cells.size(), "all pieces marked for demolition")
	if not await _wait(func() -> bool: return game.demolish.is_empty() and game.stock.wood > wood_before + 2, 6000):
		_fail("demolish left: %s, wood %d" % [game.demolish.keys(), game.stock.wood])
		return
	for c: Vector3i in cells:
		_check(not world.props.has(c) and not world.is_solid(c), "%s removed" % cells[c])
	if not failed:
		print("test_pieces OK")
	quit(1 if failed else 0)


func _wait(done: Callable, frames: int) -> bool:
	for i in frames:
		await process_frame
		if done.call():
			return true
	return false


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		failed = true


func _fail(msg: String) -> void:
	printerr("FAIL: ", msg)
	quit(1)
