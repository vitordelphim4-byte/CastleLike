extends Control
## Player input.
## Normal: click/box select (left), move order (right).
## Area mode (Game.pending_area): drag over ground tiles to mark a task area; wheel = dig depth.
## Build mode (B, piece picked in the build menu): drag on a layer to place blueprints; wheel or +/- =
## height; R rotates; Shift+drag erases plans. X toggles the demolish tool (drag marks built pieces,
## Shift+drag unmarks). Roof tool: drag over the wall tops of a building (R turns the ridge).
## Right click / Esc leaves area and build modes.

const CLICK_RADIUS := 30.0

var drag_start := Vector2.ZERO
var dragging := false
var start_cell := Vector3i.ZERO  # cell where an area/build drag started
var has_start := false
var hover_cell := Vector3i.ZERO
var hover_normal := Vector3i.ZERO  # build mode: face of the surface under the mouse
var start_normal := Vector3i.ZERO
var has_hover := false
var preview: Array[Node3D] = []


func _ready() -> void:
	Game.mode_changed.connect(_update_preview)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_B:
				Game.set_building(not Game.building)
			KEY_T:
				get_tree().get_first_node_in_group("work_tab").toggle()
			KEY_R:
				if Game.building:
					Game.build_rot = (Game.build_rot + 1) % Game.ROT_DIRS.size()
					Game.mode_changed.emit()
			KEY_X:
				if Game.building:
					Game.build_tool = "build" if Game.build_tool == "demolish" else "demolish"
					Game.mode_changed.emit()
			KEY_ESCAPE:
				var panel := get_tree().get_first_node_in_group("station_panel")
				if Game.building or Game.pending_area:
					Game.set_building(false)
				elif panel and panel.visible:
					panel.close()
				else:
					get_tree().get_first_node_in_group("pause_menu").open()
			KEY_SPACE:
				Game.toggle_game_pause()
			KEY_1, KEY_2, KEY_3:
				Game.set_speed(e.keycode - KEY_0)
			KEY_EQUAL, KEY_KP_ADD, KEY_PAGEUP:
				_adjust_size(1)
			KEY_MINUS, KEY_KP_SUBTRACT, KEY_PAGEDOWN:
				_adjust_size(-1)
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] \
			and _adjust_size(1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -1):
		get_viewport().set_input_as_handled()  # don't zoom the camera
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			drag_start = e.position
			dragging = true
			has_start = has_hover
			start_cell = hover_cell
			start_normal = hover_normal
		else:
			# Finish while `dragging` is still true: the drag rect depends on it.
			if Game.pending_area:
				_finish_area()
			elif Game.building:
				_finish_build(e.shift_pressed)
			else:
				_select(Rect2(drag_start, e.position - drag_start).abs(), e.shift_pressed)
			dragging = false
			has_start = false
			_update_preview()
		queue_redraw()
	elif e is InputEventMouseMotion:
		if _cell_mode():
			_update_hover(e.position)
			_update_preview()
		elif dragging:
			queue_redraw()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
		if _cell_mode():
			Game.set_building(false)
			return
		var hit := _raycast(e.position)
		if hit:
			for w: Worker in get_tree().get_nodes_in_group("workers"):
				if w.selected:
					w.move_to(hit.position + hit.normal * 0.5)


# Build height or dig depth, depending on mode. False if neither applies.
func _adjust_size(step: int) -> bool:
	if Game.building:
		Game.build_height = clampi(Game.build_height + step, 1, 10)
	elif Game.pending_area.get("kind") == "dig":
		Game.dig_depth = clampi(Game.dig_depth + step, 1, 12)
	else:
		return false
	Game.mode_changed.emit()
	return true


func _cell_mode() -> bool:
	return Game.building or not Game.pending_area.is_empty()


# Area mode: the ground block under the mouse. Build mode: the empty cell against the face under
# the mouse; while dragging, the cell on the drag's starting layer.
func _update_hover(screen_pos: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if Game.building and dragging and has_start:
		var hit_plane = Plane(Vector3.UP, start_cell.y).intersects_ray(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
		if hit_plane != null:
			hover_cell = Vector3i(floori(hit_plane.x), start_cell.y, floori(hit_plane.z))
		return
	if Game.building:
		# Grid walk so blueprints and pieces count as surfaces too (they have no collision).
		var hit := Game.world.raycast_cells(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos),
			func(c: Vector3i) -> bool: return Game.world.is_solid(c) or Game.blueprints.has(c) or Game.world.props.has(c))
		has_hover = not hit.is_empty() and hit.normal != Vector3i.ZERO
		if has_hover:
			# Demolish targets what you point at; building goes against the face you point at.
			hover_cell = hit.cell if Game.build_tool == "demolish" else hit.cell + hit.normal
			hover_normal = hit.normal
		return
	var hit := _raycast(screen_pos)
	has_hover = not hit.is_empty()
	if has_hover:
		hover_cell = Vector3i((hit.position - hit.normal * 0.5).floor())


func _drag_rect() -> Rect2i:
	var a := Vector2i(start_cell.x, start_cell.z) if dragging and has_start else Vector2i(hover_cell.x, hover_cell.z)
	var b := Vector2i(hover_cell.x, hover_cell.z)
	var lo := a.min(b)
	return Rect2i(lo, a.max(b) - lo + Vector2i.ONE)


# Layer the drag works on: where it started, or under the mouse before pressing.
func _layer() -> int:
	return start_cell.y if dragging and has_start else hover_cell.y


func _build_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var r := _drag_rect()
	var y0 := _layer()
	# Height stacks blocks and ladders (and demolish layers); windows, doors, stairs... stay one high.
	var height := Game.build_height if Game.build_tool == "demolish" or Pieces.stacks(Game.build_item) else 1
	for x in range(r.position.x, r.end.x):
		for z in range(r.position.y, r.end.y):
			for h in height:
				cells.append(Vector3i(x, y0 + h, z))
	return cells


func _update_preview() -> void:
	for m in preview:
		m.queue_free()
	preview.clear()
	if not _cell_mode() or not has_hover:
		return
	if Game.building:
		var erase := Input.is_key_pressed(KEY_SHIFT)
		if Game.build_tool == "demolish":
			var cells := {}
			for c in _build_cells():
				if Game.demolish_target(c) != null:
					cells[c] = Color(1, 1, 1) if erase else Game.DEMOLISH_COLOR
			preview = Game.ghost(cells, true)
		elif Game.build_tool == "roof":
			preview = Game.ghost_pieces(Game.roof_plan(_drag_rect(), _layer()))
		elif erase:
			var cells := {}
			for c in _build_cells():
				cells[c] = Game.DEMOLISH_COLOR
			preview = Game.ghost(cells)
		else:
			var plan := {}
			var dir: Vector3i = -(start_normal if dragging and has_start else hover_normal) \
				if Pieces.shape(Game.build_item).get("climb", false) else Game.ROT_DIRS[Game.build_rot]
			for c in _build_cells():
				plan[c] = {"item": Game.build_item, "dir": dir if dir.y == 0 else Game.ROT_DIRS[Game.build_rot]}
			preview = Game.ghost_pieces(plan)
	elif Game.pending_area.kind == "dig":
		var cells := Game.dig_cells(_drag_rect(), Game.dig_depth)
		for c: Vector3i in cells:
			cells[c] = Game.DIG_COLOR
		preview.append(Game.overlay(VoxelMesh.shell(cells, false, 0.03, 0.53)))
	else:
		var mesh := VoxelMesh.shell(Game.tiles(_drag_rect(), Color(Game.ORDER_COLORS[Game.pending_area.kind], 0.5)), true, 0.03, 0.45)
		if mesh:
			preview.append(Game.overlay(mesh))


func _finish_area() -> void:
	if has_start and has_hover:
		Game.finish_area(_drag_rect())
	else:
		Game.cancel_area()


func _finish_build(erase: bool) -> void:
	if not (has_start and has_hover):
		return
	if Game.build_tool == "roof":
		Game.plan_roof(_drag_rect(), _layer())
	elif Game.build_tool == "demolish":
		Game.mark_demolish(_build_cells(), not erase)
	elif erase:
		Game.erase_blueprints(_build_cells())
	else:
		Game.place_blueprints(_build_cells(), -start_normal)  # ladders lean on the clicked face


func _select(rect: Rect2, additive: bool) -> void:
	var cam := get_viewport().get_camera_3d()
	var is_click := rect.size.length() < 5
	if is_click and _open_station(rect.position):
		return
	var best: Worker = null
	var best_d := CLICK_RADIUS
	for w: Worker in get_tree().get_nodes_in_group("workers"):
		if not additive:
			w.selected = false
		var center: Vector3 = w.global_position + Vector3.UP * 0.7
		if cam.is_position_behind(center):
			continue
		var sp := cam.unproject_position(center)
		if is_click:
			var d := sp.distance_to(rect.position)
			if d < best_d:
				best_d = d
				best = w
		elif rect.has_point(sp):
			w.selected = true
	if best:
		best.selected = true


# Clicked a workstation: open its panel.
func _open_station(screen_pos: Vector2) -> bool:
	var cam := get_viewport().get_camera_3d()
	var w := Game.world
	var hit := w.raycast_cells(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos),
		func(c: Vector3i) -> bool: return w.is_solid(c) or w.props.has(c))
	if hit.is_empty() or not w.props.has(hit.cell) or not Crafting.is_station(w.props[hit.cell].item):
		return false
	get_tree().get_first_node_in_group("station_panel").open(w.props[hit.cell].base)
	return true


func _raycast(screen_pos: Vector2) -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 500
	return cam.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))


func _draw() -> void:
	if dragging and not _cell_mode():
		var r := Rect2(drag_start, get_local_mouse_position() - drag_start).abs()
		draw_rect(r, Color(0.3, 1, 0.4, 0.15))
		draw_rect(r, Color(0.3, 1, 0.4), false, 1.0)
