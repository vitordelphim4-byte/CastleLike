class_name UiDrag
## Lets a panel be moved and resized with the mouse. Drag the frame, the title or any empty spot to
## move it (labels let clicks through; buttons and lists keep theirs). Drag the bottom-right iron
## corner to resize it. Panels stay on screen and never shrink below their content.

const GRIP := 20  # px from the bottom-right corner that resize instead of move


static func attach(p: Control) -> void:
	var st := {"mode": "", "grab": Vector2.ZERO}
	p.gui_input.connect(func(e: InputEvent) -> void: handle(p, e, st))
	p.draw.connect(_draw_grip.bind(p))


static func handle(p: Control, e: InputEvent, st: Dictionary) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		st.mode = ""
		if e.pressed:
			_unanchor(p)
			var corner: Vector2 = p.size - e.position
			st.mode = "resize" if _in_grip(p, e.position) else "move"
			st.grab = corner if st.mode == "resize" else e.position
		p.accept_event()
	elif e is InputEventMouseMotion:
		if st.mode == "move":
			var room := (p.get_viewport_rect().size - p.size).max(Vector2.ZERO)
			p.position = (p.position + e.position - st.grab).round().clamp(Vector2.ZERO, room)
		elif st.mode == "resize":
			p.size = (e.position + st.grab).round().min(p.get_viewport_rect().size - p.position)
		var resizing: bool = st.mode == "resize" or (st.mode == "" and _in_grip(p, e.position))
		p.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE if resizing else Control.CURSOR_ARROW


static func _in_grip(p: Control, at: Vector2) -> bool:
	var c := p.size - at
	return c.x < GRIP and c.y < GRIP


# Scene anchors (centered, right side, full height) would fight a moved panel: pin it top-left
# where it is now.
static func _unanchor(p: Control) -> void:
	var r := Rect2(p.position, p.size)
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.grow_horizontal = Control.GROW_DIRECTION_END
	p.grow_vertical = Control.GROW_DIRECTION_END
	p.position = r.position
	p.size = r.size


# Grip: a small triangle of rivet dots on the bottom-right iron corner (panel art has a 2 px shadow).
static func _draw_grip(p: Control) -> void:
	for d: Vector2 in [Vector2(6, 6), Vector2(10, 6), Vector2(6, 10), Vector2(14, 6), Vector2(10, 10), Vector2(6, 14)]:
		p.draw_rect(Rect2(p.size - d - Vector2(2, 2), Vector2(2, 2)), UiTheme.RIVET)
