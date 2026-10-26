extends PanelContainer
## Debug map only (debug.tscn): buttons to test the systems quickly. F1 shows / hides it.
## Time (skip hours, noon / midnight, 10x speed), hunger, resources, crops and bushes, animals,
## seeing inside the ground (the hill west of the stockpile, Main._build_mine_area).

var status := Label.new()


func _ready() -> void:
	add_theme_stylebox_override("panel", preload("res://scripts/build_menu.gd").panel_style())
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "DEBUG  (F1 esconde)"
	title.add_theme_color_override("font_color", preload("res://scripts/build_menu.gd").GOLD)
	box.add_child(title)
	_row(box, "Tempo", [
		["+1 h", _skip.bind(1.0)], ["+6 h", _skip.bind(6.0)], ["+1 dia", _skip.bind(24.0)],
		["Meio-dia", _set_time.bind(0.5)], ["Meia-noite", _set_time.bind(0.0)], ["10x", Game.set_speed.bind(10)],
	])
	_row(box, "Fome", [
		["Liga/desliga", func() -> void: Game.hunger = not Game.hunger],
		["Todos com fome", _feed.bind(0.25)], ["Famintos", _feed.bind(0.0)], ["Alimentar", _feed.bind(1.0)],
	])
	_row(box, "Recursos", [
		["Infinito liga/desliga", func() -> void:
			Game.infinite = not Game.infinite
			Game.changed.emit()],
		["+10 de tudo", _fill], ["Esvaziar estoque", _empty],
	])
	_row(box, "Plantas", [["Amadurecer plantações", _ripen], ["Frutas voltam", _regrow]])
	_row(box, "Animais", [
		["+ Coelho", _spawn.bind("rabbit")], ["+ Cervo", _spawn.bind("deer")], ["+ Javali", _spawn.bind("boar")],
		["Matar o mais próximo", _kill_nearest],
	])
	_row(box, "Visão", [
		["Ir ao morro", _go_hill], ["Aldeão na câmara", _villager_in],
		["Corte: túnel", _cut.bind(2)], ["Corte: caverna", _cut.bind(6)], ["Sem corte", _cut.bind(-1)],
	])
	_row(box, "", [
		["Cavar túnel (com corte)", _dig_tunnel], ["Raio-X no cursor", func() -> void:
			Game.world.xray_cursor = not Game.world.xray_cursor
			Game.mode_changed.emit()],
	])
	_row(box, "Prédio", [
		["Ir ao prédio", _go_tower], ["Térreo", _view_tower.bind(3)], ["Paredes baixas", _view_tower.bind(1)],
		["1º andar", _view_tower.bind(7)],
	])
	status.add_theme_font_size_override("font_size", 13)
	box.add_child(status)
	var t := Timer.new()
	t.wait_time = 0.5
	t.ignore_time_scale = true
	t.autostart = true
	t.timeout.connect(_refresh)
	add_child(t)
	_refresh()
	_place.call_deferred()


# Bottom-right corner, above the hint line; done once the buttons exist so the size is known.
func _place() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	position.y -= 90


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F1:
		visible = not visible
		get_viewport().set_input_as_handled()


func _row(box: VBoxContainer, label: String, buttons: Array) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(70, 0)
	row.add_child(l)
	for b: Array in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func() -> void:
			b[1].call()
			_refresh())
		row.add_child(btn)


func _refresh() -> void:
	status.text = "%s · velocidade %dx · fome %s · infinito %s · animais %d (+%d carcaças)" % [
		Game.clock_text(), Game.speed, "ligada" if Game.hunger else "desligada", "sim" if Game.infinite else "não",
		get_tree().get_nodes_in_group("animals").size(), get_tree().get_nodes_in_group("corpses").size()]


func _skip(hours: float) -> void:
	Game.time_of_day += hours / 24.0
	while Game.time_of_day >= 1.0:
		Game.time_of_day -= 1.0
		Game.day += 1


func _set_time(t: float) -> void:
	if t < Game.time_of_day:
		Game.day += 1
	Game.time_of_day = t


func _feed(level: float) -> void:
	for w: Worker in get_tree().get_nodes_in_group("workers"):
		w.food = level


func _fill() -> void:
	for kind: String in Game.RESOURCES:
		Game.store(kind, 10)


func _empty() -> void:
	for z in Game.zones:
		for t: Dictionary in z.tiles.values():
			t.kind = ""
			t.n = 0
	Game._stock_changed()


func _ripen() -> void:
	for f in Game.farms:
		for t: Dictionary in f.tiles.values():
			if t.plant:
				t.sown -= Farming.CROPS[t.plant].grow_days
	Game.orders_changed.emit()


func _regrow() -> void:
	for t: Dictionary in Game.world.trees.values():
		if t.kind == "bush":
			t.amount = ResourceNode.amount_for(t)
			t.erase("regrow_at")
	for n: ResourceNode in Game.world.tree_nodes.values():
		if n.kind == "berries":
			n._show_bush()


func _spawn(species: String) -> void:
	var rig: Node3D = get_node("../CameraRig")
	var p := rig.position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
	p.y = Game.world.top_at(floori(p.x), floori(p.z))
	Animal.spawn(get_node("../Animals"), Game.world, species, Vector3(floorf(p.x) + 0.5, p.y, floorf(p.z) + 0.5))


func _kill_nearest() -> void:
	var rig: Node3D = get_node("../CameraRig")
	var best: Animal = null
	for a: Animal in get_tree().get_nodes_in_group("animals"):
		if best == null or a.position.distance_to(rig.position) < best.position.distance_to(rig.position):
			best = a
	if best:
		best.hurt(999, rig)


# --- Seeing inside (Phase 9): scenarios on the debug hill ---

func _go_hill() -> void:
	var r: Rect2i = get_parent().mine.rect
	var rig: Node3D = get_node("../CameraRig")
	rig.position.x = r.get_center().x + 6  # a bit east: the tunnel mouth faces the camera's side
	rig.position.z = r.get_center().y + 4


# First villager into the chamber, selected: shows the outline and the automatic x-ray hole while
# it walks back out to work.
func _villager_in() -> void:
	var w: Worker = get_tree().get_nodes_in_group("workers")[0]
	for o: Worker in get_tree().get_nodes_in_group("workers"):
		o.selected = o == w
	w.position = get_parent().mine.chamber
	w.move_to(w.position)
	_go_hill()


# Layers above the hill's ground level (-1 = off): 2 = tunnel ceiling gone, 6 = sealed cave open.
func _cut(above_ground: int) -> void:
	Game.world.set_cut(World.SY if above_ground < 0 else get_parent().mine.y + above_ground)
	Game.mode_changed.emit()
	_go_hill()


# Cut at the tunnel and mark a 4-block, 2-high branch going north out of the chamber (side digging
# under solid stone).
func _dig_tunnel() -> void:
	_cut(2)
	Game.dig_depth = 2
	var c: Vector3 = get_parent().mine.chamber
	Game.add_order("dig", Rect2i(floori(c.x), floori(c.z) - 7, 1, 4))


# --- The 2-floor building (Main._build_tower) ---

func _go_tower() -> void:
	var r: Rect2i = get_parent().tower.rect
	var rig: Node3D = get_node("../CameraRig")
	rig.position.x = r.get_center().x
	rig.position.z = r.get_center().y + 3


# Cut this many layers above the building's ground: 3 = ground floor (slab above hidden), 1 = its
# walls cut low, 7 = first floor.
func _view_tower(above_ground: int) -> void:
	_go_tower()
	Game.world.set_cut(get_parent().tower.y + above_ground)
	Game.mode_changed.emit()
