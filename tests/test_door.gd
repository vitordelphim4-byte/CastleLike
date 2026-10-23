extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_door.gd
## A pen of 2-high walls with a 1-wide gap. A door blueprint in the gap must not cut the path (only solid
## plans block); the built door must be walked through and swing open while doing so.

var failed := false


func _initialize() -> void:
	root.add_child(load("res://debug.tscn").instantiate())
	var game := root.get_node("Game")
	await process_frame
	var world: World = game.world
	var workers := root.get_tree().get_nodes_in_group("workers")
	for w in workers:
		for work in w.priorities:
			w.priorities[work] = 0
	var s := Vector3i(game.stockpile.floor())
	var y := world.top_at(s.x, s.z)
	var wall_z := s.z - 6
	var gap := Vector3i(s.x, y, wall_z)
	# Pen of 2-high walls (x -4..4, z wall_z-8..wall_z); the gap is the only way in.
	for x in range(s.x - 4, s.x + 5):
		for z in range(wall_z - 8, wall_z + 1):
			var edge := x == s.x - 4 or x == s.x + 4 or z == wall_z - 8 or z == wall_z
			if edge and Vector3i(x, y, z) != gap:
				for h in 2:
					world.set_block(Vector3i(x, y + h, z), World.BRICK)
	var a := Vector3(s.x + 0.5, y, wall_z + 3.5)  # stockpile side
	var b := Vector3(s.x + 0.5, y, wall_z - 3.5)  # far side

	game.build_item = "wood_door"
	game.place_blueprints([gap] as Array[Vector3i])
	_check(game.blueprints.has(gap), "door planned in the gap")
	_check(world.find_path(a, b)[-1].distance_to(b) < 0.1, "door blueprint doesn't block the gap")

	game.build_item = "wood_block"
	game.place_blueprints([gap + Vector3i.UP * 3] as Array[Vector3i])  # unrelated, just must not crash
	game.erase_blueprints([gap] as Array[Vector3i])
	game.place_blueprints([gap] as Array[Vector3i])
	_check(game.blueprints[gap].item == "wood_block" and world.find_path(a, b)[-1].distance_to(b) > 0.5,
		"a wall-block blueprint in the gap does block it")
	game.erase_blueprints([gap] as Array[Vector3i])

	world.add_prop(gap, "wood_door", Vector3i.FORWARD)
	_check(world.find_path(a, b)[-1].distance_to(b) < 0.1, "built door is walkable")
	var w = workers[0]
	w.position = a
	w.move_to(b)
	var opened := false
	for frame in 600:
		await process_frame
		var hinge: Node3D = world.prop_nodes[gap].get_node("Hinge")
		opened = opened or absf(hinge.rotation.y) > 1.0
		if w.position.distance_to(b) < 0.1:
			break
	_check(w.position.distance_to(b) < 0.1, "villager walked through the door, ended at %s" % w.position)
	_check(opened, "door swung open while the villager passed")
	if not failed:
		print("test_door OK")
	quit(1 if failed else 0)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		failed = true
