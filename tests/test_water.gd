extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_water.gd
## Phase 10e1, Minecraft water rules on the flat debug map, stepping Fluids by hand:
## spreads 7 blocks losing a level each, dries up when its source goes, falls before spreading,
## heads for a nearby drop, never makes a new source between two, floods a hole dug beside a pool.

var world: World
var y := 0


func _initialize() -> void:
	root.add_child(load("res://debug.tscn").instantiate())
	await process_frame
	world = root.get_node("Game").world
	var o := Vector3i(40, 0, -60)  # empty plain, away from everything
	y = world.top_at(o.x, o.z)
	for t: Vector3i in world.trees.keys():
		if absi(t.x - o.x - 20) < 30 and absi(t.z - o.z - 10) < 20:
			world.remove_tree(t)
	world.fluids.active.clear()

	# Spread: 7 blocks, one level less per block.
	var s := o
	_place({s + Vector3i(0, y, 0): World.WATER})
	_steps(10)
	for d in range(1, 9):
		var t := world.get_block(s + Vector3i(d, y, 0))
		if World.water_level(t) != maxi(0, 8 - d):
			return _fail("spread: %d blocks out has level %d, want %d" % [d, World.water_level(t), maxi(0, 8 - d)])
	# Dries up without its source.
	_place({s + Vector3i(0, y, 0): World.AIR})
	_steps(12)
	if _water_around(s + Vector3i(0, y, 0), 8) > 0:
		return _fail("flowing water left after removing the source")

	# Falls before spreading, spreads where it lands.
	var f := o + Vector3i(20, y + 3, 0)
	_place({f: World.WATER})
	_steps(1)
	if world.get_block(f + Vector3i.DOWN) != World.FALLING or world.get_block(f + Vector3i.RIGHT) != World.AIR:
		return _fail("source in the air should fall, not spread")
	_steps(6)
	if world.get_block(Vector3i(f.x, y, f.z)) != World.FALLING or world.get_block(Vector3i(f.x + 1, y, f.z)) != World.FLOW_7:
		return _fail("falling water should land and spread: %d / %d" % [world.get_block(Vector3i(f.x, y, f.z)), world.get_block(Vector3i(f.x + 1, y, f.z))])
	_place({f: World.AIR})
	_steps(15)

	# Heads for a drop 3 blocks away, not the other way.
	var h := o + Vector3i(0, y, 10)
	_place({h + Vector3i(3, -1, 0): World.AIR})
	_place({h: World.WATER})
	_steps(2)
	if world.get_block(h + Vector3i.RIGHT) != World.FLOW_7 or world.get_block(h + Vector3i.LEFT) != World.AIR:
		return _fail("water should head for the drop: right %d, left %d" % [world.get_block(h + Vector3i.RIGHT), world.get_block(h + Vector3i.LEFT)])

	# No new source between two sources.
	var n := o + Vector3i(20, y, 10)
	_place({n: World.WATER, n + Vector3i(2, 0, 0): World.WATER})
	_steps(6)
	if world.get_block(n + Vector3i.RIGHT) != World.FLOW_7:
		return _fail("between two sources: want flowing 7, got %d" % world.get_block(n + Vector3i.RIGHT))

	# A pool in a pit floods a hole dug beside it.
	var p := o + Vector3i(0, y - 1, 20)
	var pool := {}
	for x in 3:
		for z in 3:
			pool[p + Vector3i(x, 0, z)] = World.WATER
	_place(pool)
	_steps(3)
	var wall := p + Vector3i(3, 0, 1)
	if world.is_water(world.get_block(wall)):
		return _fail("the pool leaked before digging")
	_place({wall: World.AIR})
	_steps(2)
	if world.get_block(wall) != World.FLOW_7:
		return _fail("digging beside the pool: hole has %d, want flowing 7" % world.get_block(wall))
	print("test_water OK")
	quit()


func _place(cells: Dictionary) -> void:
	world.set_blocks(cells)


func _steps(n: int) -> void:
	for i in n:
		world.fluids.step()


func _water_around(c: Vector3i, r: int) -> int:
	var count := 0
	for x in range(-r, r + 1):
		for z in range(-r, r + 1):
			count += int(World.is_water(world.get_block(c + Vector3i(x, 0, z))))
	return count


func _fail(msg: String) -> void:
	printerr("FAIL: ", msg)
	quit(1)
