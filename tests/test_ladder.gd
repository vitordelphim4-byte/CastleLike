extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_ladder.gd
## A 4-high wall with a ladder blueprint in front and a 3-block tower planned on top of the wall.
## The tower top (wall + 3) is only reachable standing on the wall, so workers must build the
## ladder bottom-up, climb it and walk onto the wall. 120 simulated seconds.


func _initialize() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	var game := root.get_node("Game")
	await process_frame
	var world: World = game.world
	var s := Vector3i(game.stockpile.floor())
	var wx := s.x + 4
	var z0 := s.z
	var y0 := world.top_at(s.x, s.z)
	# Flat ground around the site, then the wall along z.
	for x in range(wx - 4, wx + 3):
		for z in range(z0 - 4, z0 + 5):
			for y in range(y0, World.SY):
				world.set_block(Vector3i(x, y, z), World.AIR)
			world.set_block(Vector3i(x, y0 - 1, z), World.DIRT)
	for z in range(z0 - 2, z0 + 3):
		for y in range(y0, y0 + 4):
			world.set_block(Vector3i(wx, y, z), World.BRICK)
	game.store("wood", 20)

	game.build_item = "ladder"
	var ladder: Array[Vector3i] = []
	for y in range(y0, y0 + 4):
		ladder.append(Vector3i(wx - 1, y, z0))
	game.place_blueprints(ladder, Vector3i.RIGHT)
	game.build_item = "wood_block"
	var tower: Array[Vector3i] = []
	for y in range(y0 + 4, y0 + 7):
		tower.append(Vector3i(wx, y, z0 + 2))
	game.place_blueprints(tower)

	var climbed := false
	for frame in 7200:
		await process_frame
		for w in root.get_tree().get_nodes_in_group("workers"):
			climbed = climbed or w.position.y >= y0 + 4
		var done := tower.all(func(c: Vector3i) -> bool: return world.get_block(c) == World.WOOD) \
			and ladder.all(func(c: Vector3i) -> bool: return world.is_ladder(c))
		if done:
			if not climbed:
				printerr("FAIL: tower built but nobody stood on the wall")
				quit(1)
				return
			print("test_ladder OK (frame %d)" % frame)
			quit()
			return
	printerr("FAIL: blueprints left %s, climbed %s" % [game.blueprints.keys(), climbed])
	quit(1)
