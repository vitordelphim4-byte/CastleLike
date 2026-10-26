extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s tests/test_view_cut.gd
## Phase 9: layer cut + mining inside a hill. On the flat debug map a stone hill 3 high is cut at
## its middle layer: picking stops under the cut, the cut plane gets a cap, villagers above it
## hide, a dig order made under the cut becomes a 2-high tunnel that a lone miner digs out from
## the side (blocks with solid stone above), and the side slider drives the cut. 120 simulated s.


func _initialize() -> void:
	root.add_child(load("res://debug.tscn").instantiate())
	var game := root.get_node("Game")
	await process_frame
	var world: World = game.world
	var s := Vector3i(game.stockpile.floor())
	var top := world.top_at(s.x + 6, s.z + 6)  # feet level on the plain
	for x in range(s.x + 4, s.x + 9):
		for z in range(s.z + 4, s.z + 7):
			for h in 3:
				world.set_block(Vector3i(x, top + h, z), World.STONE)

	world.set_cut(top + 2)  # hides the hill's top layer
	var hit := world.raycast_cells(Vector3(s.x + 6.5, 100, s.z + 5.5), Vector3.DOWN, world.is_solid)
	if hit.is_empty() or hit.cell.y != top + 1:
		return _fail("pick under the cut should hit y %d, got %s" % [top + 1, hit])
	for i in 5:
		await process_frame  # caps stream in
	var c := Vector2i((s.x + 6) >> 4, (s.z + 5) >> 4)
	if not world.caps.get(c):
		return _fail("no cap mesh on the cut plane")
	var miner = root.get_tree().get_nodes_in_group("workers")[0]
	var probe := Node3D.new()  # something standing on the hidden top layer
	root.get_tree().get_first_node_in_group("cut_hide_children").add_child(probe)
	probe.position = Vector3(s.x + 6.5, top + 3, s.z + 5.5)
	world._apply_cut_visibility()
	if probe.visible or not miner.visible:
		return _fail("visibility: probe above cut %s, miner on the ground %s" % [probe.visible, miner.visible])
	probe.queue_free()

	game.dig_depth = 2
	var order: Dictionary = game.add_order("dig", Rect2i(s.x + 4, s.z + 5, 5, 1))
	if order.cells.size() != 10:
		return _fail("tunnel order should mark 5x2 blocks under the cut, got %d" % order.cells.size())
	for w in root.get_tree().get_nodes_in_group("workers"):
		for work in w.priorities:
			w.priorities[work] = 0
	miner.priorities.dig = 1
	for frame in 7200:
		await process_frame
		if order.cells.is_empty():
			if not world.is_solid(Vector3i(s.x + 6, top + 2, s.z + 5)):
				return _fail("the tunnel ceiling was dug")
			world.set_cut(World.SY)
			# Side slider: dragging it cuts, the top notch shows everything, and its range following
			# the camera never moves the cut by itself.
			var bar: Node = null
			for n in root.get_node("Main/Input").get_children():
				if n.has_method("_sync"):
					bar = n
			bar.slider.value = top + 1
			if world.cut_y != top + 1:
				return _fail("slider to %d left the cut at %d" % [top + 1, world.cut_y])
			bar._ground += 7
			bar._sync()
			if world.cut_y != top + 1:
				return _fail("slider range change moved the cut to %d" % world.cut_y)
			bar.slider.value = bar.slider.max_value
			if world.cut_y != World.SY:
				return _fail("slider top should turn the cut off")
			print("test_view_cut OK (frame %d)" % frame)
			quit()
			return
	_fail("tunnel blocks left: %d, miner at %s" % [order.cells.size(), miner.position])


func _fail(msg: String) -> void:
	printerr("FAIL: ", msg)
	quit(1)
