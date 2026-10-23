extends SceneTree
## Run: godot --headless --path . -s tests/test_build_input.gd
## Feeds real mouse events to the input controller in build mode:
## dragging over 3 ground cells places 3 blueprints; clicking on top of one stacks a blueprint on it.


func _initialize() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	var game := root.get_node("Game")
	var input: Control = root.get_node("Main/Input")
	var rig: Node3D = root.get_node("Main/CameraRig")
	await process_frame
	var world: World = game.world
	# Flat 3-wide strip in front of the stockpile so the drag stays on one layer.
	var s := Vector3i(game.stockpile.floor())
	var y := world.top_at(s.x, s.z - 3)
	for x in range(s.x - 3, s.x + 4):
		for z in range(s.z - 6, s.z):
			for h in range(y, World.SY):
				world.set_block(Vector3i(x, h, z), World.AIR)
			world.set_block(Vector3i(x, y - 1, z), World.DIRT)
	rig.position = Vector3(s.x, y, s.z - 3)
	rig.distance = 12.0
	rig._update_cam()
	await process_frame
	var cam := root.get_viewport().get_camera_3d()

	game.set_building(true)
	var a := cam.unproject_position(Vector3(s.x - 1 + 0.5, y, s.z - 3 + 0.5))
	var b := cam.unproject_position(Vector3(s.x + 1 + 0.5, y, s.z - 3 + 0.5))
	_mouse(input, a, true)
	_motion(input, b)
	_mouse(input, b, false)
	var row: Array[Vector3i] = [Vector3i(s.x - 1, y, s.z - 3), Vector3i(s.x, y, s.z - 3), Vector3i(s.x + 1, y, s.z - 3)]
	_check(game.blueprints.size() == 3 and row.all(func(c: Vector3i) -> bool: return game.blueprints.has(c)),
		"drag places 3 blueprints in a row, got %s" % [game.blueprints.keys()])

	# Click the top face of the middle blueprint -> new blueprint one layer up.
	var top := cam.unproject_position(Vector3(s.x + 0.5, y + 1, s.z - 3 + 0.5))
	_motion(input, top)
	_mouse(input, top, true)
	_mouse(input, top, false)
	_check(game.blueprints.has(Vector3i(s.x, y + 1, s.z - 3)),
		"click on blueprint stacks one above it; blueprints: %s, hover %s" % [game.blueprints.keys(), input.hover_cell])
	# Windows ignore the height setting: one window, not a stack.
	game.build_item = "wood_window"
	game.build_height = 3
	var side := cam.unproject_position(Vector3(s.x + 2 + 0.5, y, s.z - 3 + 0.5))
	_mouse(input, side, true)
	_mouse(input, side, false)
	var windows: Array = game.blueprints.keys().filter(func(c: Vector3i) -> bool: return game.blueprints[c].item == "wood_window")
	_check(windows.size() == 1, "window placed once despite height 3, got %d" % windows.size())
	if not failed:
		print("test_build_input OK")
	quit(1 if failed else 0)


var failed := false


func _motion(input: Control, pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	input._unhandled_input(e)


func _mouse(input: Control, pos: Vector2, pressed: bool) -> void:
	_motion(input, pos)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	input._unhandled_input(e)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: ", msg)
		failed = true
