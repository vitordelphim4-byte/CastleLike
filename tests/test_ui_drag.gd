extends SceneTree
## Run: godot --headless --path . -s tests/test_ui_drag.gd
## UiDrag: dragging a panel moves it (and unpins its scene anchors), dragging the bottom-right
## corner resizes it, it can't leave the screen or shrink below its content.

var failed := false


func _initialize() -> void:
	var p := PanelContainer.new()
	var l := Label.new()
	l.text = "Painel de teste"
	p.add_child(l)
	root.add_child(p)
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)  # like the work tab
	UiDrag.attach(p)
	await process_frame
	p.position = Vector2(100, 100)
	p.size = Vector2(300, 120)

	_drag(Vector2(150, 150), Vector2(200, 180))  # on the label: moves
	_check(p.position == Vector2(150, 130), "move: %s" % p.position)
	_check(p.anchor_left == 0.0 and p.anchor_right == 0.0, "anchors unpinned: %s" % p.anchor_left)
	_check(p.size == Vector2(300, 120), "move keeps size: %s" % p.size)

	var corner := p.position + p.size - Vector2(5, 5)
	_drag(corner, corner + Vector2(40, 20))
	_check(p.size == Vector2(340, 140), "resize: %s" % p.size)
	_check(p.position == Vector2(150, 130), "resize keeps position: %s" % p.position)

	corner = p.position + p.size - Vector2(5, 5)
	_drag(corner, corner - Vector2(1000, 1000))
	_check(p.size == p.get_combined_minimum_size(), "no smaller than content: %s" % p.size)

	_drag(p.position + Vector2(5, 5), Vector2(-500, -500))
	_check(p.position == Vector2.ZERO, "stays on screen: %s" % p.position)

	print("FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _drag(from: Vector2, to: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	root.push_input(down)
	var move := InputEventMouseMotion.new()
	move.position = to
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(move)
	var up := down.duplicate()
	up.pressed = false
	up.position = to
	root.push_input(up)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failed = true
		print("FAIL: ", what)
