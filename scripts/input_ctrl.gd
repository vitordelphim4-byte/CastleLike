extends Control
## Player input.
## Normal: click/box select (left), move order (right).
## Area mode (Game.pending_area): drag over ground tiles to mark a task area; wheel = dig depth.
## Build mode (B, piece picked in the build menu): drag on a layer to place blueprints; wheel or +/- =
## height; R rotates; Shift+drag erases plans. X toggles the demolish tool (drag marks built pieces,
## Shift+drag unmarks). Roof tool: drag over the wall tops of a building (R turns the ridge).
## Right click / Esc leaves area and build modes.
## Hovering a stockpile or field tile shows what's on it (amount / crop growth).
## Right click with villagers selected: on a tree / bush / animal / corpse / ripe crop / stone or ore
## block they do that job right away (RimWorld "prioritize"); anywhere else they walk there.
## Hunt tool: a click on an animal marks (or unmarks) just that animal.
## Seeing inside (Phase 9): PageDown / PageUp (or the slider on the right, ViewSlider) lower / raise
## the layer cut one block (Shift = 5), Home turns it off; what's above the cut isn't drawn and
## can't be clicked. V toggles the cursor x-ray; selected villagers hidden behind terrain always
## get an x-ray hole.

const CLICK_RADIUS := 30.0
const XRAY_DEPTH := 6.0  # cursor x-ray: how far past the surface under the mouse it sees
const CUT_ABOVE := 15  # raising the cut this far over the ground at the camera turns it off

var drag_start := Vector2.ZERO
var dragging := false
var start_cell := Vector3i.ZERO  # cell where an area/build drag started
var has_start := false
var hover_cell := Vector3i.ZERO
var hover_normal := Vector3i.ZERO  # build mode: face of the surface under the mouse
var start_normal := Vector3i.ZERO
var has_hover := false
var preview: Array[Node3D] = []
var tip := Label.new()  # hover info near the mouse


func _ready() -> void:
	Game.mode_changed.connect(_update_preview)
	tip.add_theme_stylebox_override("normal", UiTheme.parchment())
	tip.add_theme_color_override("font_color", UiTheme.INK)
	tip.add_theme_font_size_override("font_size", 16)
	tip.visible = false
	add_child(tip)
	add_child(preload("res://scripts/view_slider.gd").new())


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:  # holding repeats
		_step_cut((1 if e.keycode == KEY_PAGEUP else -1) * (5 if e.shift_pressed else 1))
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_B:
				Game.set_building(not Game.building)
			KEY_T:
				get_tree().get_first_node_in_group("work_tab").toggle()
			KEY_R:
				if Game.building:
					Game.build_rot = (Game.build_rot + 1) % Game.ROT_DIRS.size()
					Game.mode_changed.emit()
			KEY_HOME:
				Game.world.set_cut(World.SY)
				Game.mode_changed.emit()
			KEY_V:
				Game.world.xray_cursor = not Game.world.xray_cursor
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
			KEY_EQUAL, KEY_KP_ADD:
				_adjust_size(1)
			KEY_MINUS, KEY_KP_SUBTRACT:
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
		tip.visible = false
		if _cell_mode():
			_update_hover(e.position)
			_update_preview()
		elif dragging:
			queue_redraw()
		else:
			_update_tip(e.position)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
		if _cell_mode():
			Game.set_building(false)
			return
		var chosen := get_tree().get_nodes_in_group("workers").filter(func(w: Worker) -> bool: return w.selected)
		if chosen.is_empty():
			return
		var order := _pick_target(e.position)
		if order:
			var exclusive: bool = order.kind in ["gather", "butcher", "harvest", "dig"]  # one villager is enough
			for w: Worker in chosen:
				if not w.command(order.kind, order.target):
					w.move_to(order.at)
				if exclusive:
					break
			return
		var hit := _raycast(e.position)
		if hit:
			for w: Worker in chosen:
				w.move_to(hit.position + hit.normal * 0.5)


# Off -> first step down hides the ground layer at the camera; then one layer per step.
func _step_cut(step: int) -> void:
	var w := Game.world
	var top := w.top_at(floori(w.focus.x), floori(w.focus.z))
	if w.cut_y >= World.SY:
		if step > 0:
			return
		w.set_cut(top + step)
	elif w.cut_y + step > top + CUT_ABOVE:
		w.set_cut(World.SY)
	else:
		w.set_cut(w.cut_y + step)
	Game.mode_changed.emit()  # hint line + previews follow the new layer


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or Game.world == null:
		return
	var points: Array[Vector3] = []
	for w: Worker in get_tree().get_nodes_in_group("workers"):
		var head := w.global_position + Vector3.UP * 1.5
		var hidden := w.visible and (_behind_terrain(cam, w.global_position + Vector3.UP * 0.3) or _behind_terrain(cam, head))
		w.set_outline(hidden)
		if hidden and w.selected:
			points.append(w.global_position + Vector3.UP * 0.9)
	if Game.world.xray_cursor:
		var mouse := get_viewport().get_mouse_position()
		var hit := _raycast(mouse)
		if hit:
			points.append(hit.position + cam.project_ray_normal(mouse) * XRAY_DEPTH)
	Game.world.set_xray(points)


func _behind_terrain(cam: Camera3D, p: Vector3) -> bool:
	var from := cam.global_position
	var hit := Game.world.raycast_cells(from, (p - from).normalized(), Game.world.is_solid, from.distance_to(p) - 0.8)
	return not hit.is_empty()


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
	var click := drag_start.distance_to(get_viewport().get_mouse_position()) < 5
	if click and Game.pending_area.kind == "hunt":
		var order := _pick_target(drag_start)
		if order and order.kind == "hunt":
			order.target.marked = not order.target.marked
			Game.cancel_area()
			return
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
		if cam.is_position_behind(center) or not w.visible:
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
		Game.world.cut_to(best.position)
		Game.mode_changed.emit()


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


# What a right click at screen_pos points at: {kind, target, at} or {}. Animals, corpses, trees and
# bushes are picked by how close they are on screen (they have no collision); crops and blocks by
# the ground under the mouse.
func _pick_target(screen_pos: Vector2) -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	var best := {}
	var best_d := 40.0
	var things := get_tree().get_nodes_in_group("animals") + get_tree().get_nodes_in_group("corpses")
	for a: Node3D in things:
		if not a.visible:
			continue  # above the layer cut
		var c := a.global_position + Vector3.UP * 0.4
		if not cam.is_position_behind(c) and cam.unproject_position(c).distance_to(screen_pos) < best_d:
			best_d = cam.unproject_position(c).distance_to(screen_pos)
			best = {"kind": "butcher" if a.state == Animal.DEAD else "hunt", "target": a, "at": a.position}
	for n: ResourceNode in Game.world.tree_nodes.values():
		if not n.visible:
			continue
		var c := n.global_position + Vector3.UP * (0.4 if n.kind == "berries" else 1.0)
		if not cam.is_position_behind(c) and cam.unproject_position(c).distance_to(screen_pos) < best_d:
			best_d = cam.unproject_position(c).distance_to(screen_pos)
			best = {"kind": "gather" if n.kind == "berries" else "wood", "target": n, "at": n.position}
	if best:
		return best
	var hit := _raycast(screen_pos)
	if hit.is_empty():
		return {}
	var block := Vector3i((hit.position - hit.normal * 0.5).floor())
	var f := Game.farm_tile(block + Vector3i.UP)
	if f and f.plant != "" and Game.growth(f) >= 1.0 and not f.claimed:
		return {"kind": "harvest", "target": block + Vector3i.UP, "at": Vector3(block) + Vector3(0.5, 1, 0.5)}
	if Game.world.get_block(block) in [World.STONE, World.IRON_ORE, World.COAL_ORE, World.DEEPSLATE]:
		return {"kind": "dig", "target": block, "at": hit.position + hit.normal * 0.5}
	return {}


# What's on the stockpile / field tile under the mouse.
func _update_tip(screen_pos: Vector2) -> void:
	var hit := _raycast(screen_pos)
	if hit.is_empty():
		return
	var feet := Vector3i((hit.position - hit.normal * 0.5).floor()) + Vector3i.UP
	var text := ""
	var t := Game.zone_tile(feet)
	if t:
		if t.n > 0:
			text = "Estoque: %s %d/%d" % [Game.RESOURCES[t.kind].name.capitalize(), t.n, Game.RESOURCES[t.kind].per_tile]
		else:
			text = "Estoque: vazio"
	var f := Game.farm_tile(feet)
	if f:
		var crop_name: String = Farming.CROPS[f.plant].name if f.plant else Farming.CROPS[Game.farm_of(feet).crop].name
		var g := Game.growth(f)
		if f.plant == "":
			text = "Plantação: vazio (vai plantar %s)" % crop_name
		elif g >= 1.0:
			text = "%s maduro — pronto para colher" % crop_name
		else:
			var hours: float = (1.0 - g) * Farming.CROPS[f.plant].grow_days * 24.0
			text = "%s: %d%% (pronto em %.0f h)" % [crop_name, int(g * 100), ceilf(hours)]
	if text:
		tip.text = text
		tip.position = screen_pos + Vector2(18, 18)
		tip.reset_size()
		tip.visible = true


func _raycast(screen_pos: Vector2) -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	var from := cam.project_ray_origin(screen_pos)
	# Grid walk instead of physics: terrain has no collision shapes (they cost ~60% of its memory).
	var hit := Game.world.raycast_cells(from, cam.project_ray_normal(screen_pos), Game.world.is_solid, 500.0)
	if hit.is_empty() or hit.normal == Vector3i.ZERO:
		return {}
	var n := Vector3(hit.normal)
	return {"position": Vector3(hit.cell) + Vector3.ONE * 0.5 + n * 0.5, "normal": n}  # center of the face hit


func _draw() -> void:
	if dragging and not _cell_mode():
		var r := Rect2(drag_start, get_local_mouse_position() - drag_start).abs()
		draw_rect(r, Color(0.3, 1, 0.4, 0.15))
		draw_rect(r, Color(0.3, 1, 0.4), false, 1.0)
