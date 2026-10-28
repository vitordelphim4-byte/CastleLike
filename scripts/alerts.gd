extends VBoxContainer
## Alert toasts, bottom right (HUD mock): newest at the bottom, MAX_SHOWN at most (the rest fold into a
## "+N alertas" chip that expands them). Levels, each with its own icon shape:
##   danger (diamond): a villager is starving. Stays while it lasts.
##   warn (triangle): a stockpile is full, a workstation is stopped. 10 s.
##   info (octagon): not enough material for the construction plans. 6 s.
## A condition fires once when it starts; it can fire again only after it clears. Same cause = one
## toast "×N". Left click: camera goes there and selects it (repeat clicks cycle the targets).
## Right click: dismiss. Hovering pauses the timer.

const MAX_SHOWN := 4
const LIFE := {"danger": INF, "warn": 10.0, "info": 6.0}
const ICONS := {"danger": "stop", "warn": "warn", "info": "info"}
const STATION_OK := ["", "desligado", "meta atingida"]

var active := {}  # key -> alert (see _conditions) + {time_left, toast, parts, hovered, next}
var _holding := {}  # key -> true while its condition holds
var _expanded := false
var chip := Button.new()


func _ready() -> void:
	add_to_group("alerts")
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.focus_mode = Control.FOCUS_NONE
	chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	chip.add_theme_font_size_override("font_size", 12)
	chip.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	chip.pressed.connect(func() -> void:
		_expanded = not _expanded
		_layout())
	add_child(chip)
	var t := Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	t.ignore_time_scale = true  # timers run in real time, also while paused
	t.timeout.connect(_tick.bind(0.5))
	add_child(t)


func _tick(dt: float) -> void:
	var now := _conditions()
	for key: String in now:
		if key not in _holding:  # just started: fire
			_holding[key] = true
			active[key] = now[key].merged({"time_left": LIFE[now[key].level], "hovered": false, "next": 0})
		elif key in active:  # still holding: keep its text current
			for f: String in ["title", "sub", "count", "targets"]:
				active[key][f] = now[key][f]
	for key: String in _holding.keys():
		if key not in now:
			_holding.erase(key)
			if key in active and active[key].level == "danger":
				_remove(key)
	for key: String in active.keys():
		var a: Dictionary = active[key]
		if not a.hovered:
			a.time_left -= dt
		if a.time_left <= 0:
			_remove(key)
	_layout()


## What's wrong right now: key -> {level, title, sub, count, targets}.
func _conditions() -> Dictionary:
	var out := {}
	var starving := get_tree().get_nodes_in_group("workers").filter(func(w: Worker) -> bool: return w.food <= 0.0)
	if starving:
		var names := ", ".join(starving.map(func(w: Worker) -> String: return w.worker_name))
		out.starving = {"level": "danger", "count": starving.size(), "targets": starving,
			"title": "%s passando fome" % starving[0].worker_name if starving.size() == 1 else "%d aldeões passando fome" % starving.size(),
			"sub": "Fome 0% · clique para ir até lá" if starving.size() == 1 else names}
	var full := Game.zones.filter(func(z: Dictionary) -> bool: return Game.zone_used(z) >= z.tiles.size() and z.tiles.size() > 0)
	if full:
		out.stock_full = {"level": "warn", "count": full.size(), "targets": full,
			"title": "Estoque #%d cheio" % full[0].id if full.size() == 1 else "%d estoques cheios" % full.size(),
			"sub": "Marque mais estoque · clique para ver"}
	for base: Vector3i in Game.stations:
		var st: Dictionary = Game.station(base)
		if st.is_empty():
			continue
		for id: String in st.bills:
			var why := Crafting.blocker(st.bills[id], id)
			if why not in STATION_OK:
				out["station:%s" % base] = {"level": "warn", "count": 1, "targets": [base],
					"title": "%s parada" % Crafting.STATIONS[st.item].name,
					"sub": "%s: %s" % [Crafting.RECIPES[id].name, why]}
				break
	var need := {}
	for c: Vector3i in Game.blueprints:
		var info: Dictionary = Pieces.ITEMS[Game.blueprints[c].item]
		need[info.mat] = need.get(info.mat, 0) + info.cost
	for mat: String in need:
		var short: int = need[mat] - Game.stock[mat]
		if short > 0 and not Game.infinite:
			out["material:" + mat] = {"level": "info", "count": 1, "targets": [],
				"title": "Sem %s suficiente" % Game.RESOURCES[mat].name,
				"sub": "Faltam %d para os planos" % short}
	return out


func _remove(key: String) -> void:
	var a: Dictionary = active[key]
	if a.has("toast"):
		a.toast.queue_free()
	active.erase(key)


# Toasts in firing order, newest at the bottom; only the last MAX_SHOWN unless expanded.
func _layout() -> void:
	var keys := active.keys()
	var hidden := 0 if _expanded else maxi(0, keys.size() - MAX_SHOWN)
	chip.visible = keys.size() > MAX_SHOWN
	chip.text = "mostrar menos" if _expanded else "+%d alertas" % hidden
	for i in keys.size():
		var a: Dictionary = active[keys[i]]
		if not a.has("toast"):
			_make_toast(keys[i], a)
		a.toast.visible = i >= hidden
		a.parts.title.text = a.title
		a.parts.sub.text = a.sub
		a.parts.count.text = "×%d" % a.count if a.count > 1 else ""
		move_child(a.toast, -1)


func _make_toast(key: String, a: Dictionary) -> void:
	var toast := PanelContainer.new()
	toast.custom_minimum_size = Vector2(248, 48)
	toast.mouse_filter = Control.MOUSE_FILTER_STOP
	toast.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := UiTheme.card("normal")
	normal.set_content_margin_all(10)
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	var hover := UiTheme.card("hover")
	hover.set_content_margin_all(10)
	hover.content_margin_top = 4
	hover.content_margin_bottom = 4
	toast.add_theme_stylebox_override("panel", normal)
	add_child(toast)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(h)
	var icon := TextureRect.new()
	icon.texture = UiIcons.x2(UiIcons.x2(UiIcons.glyph(ICONS[a.level])))
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	var title := Label.new()
	title.clip_text = true
	title.custom_minimum_size.x = 150
	v.add_child(title)
	var sub := UiTheme.caption("")
	sub.clip_text = true
	sub.custom_minimum_size.x = 150
	v.add_child(sub)
	var count := UiTheme.num(20, UiTheme.GOLD)
	h.add_child(count)
	a.toast = toast
	a.parts = {"title": title, "sub": sub, "count": count}
	toast.mouse_entered.connect(func() -> void:
		a.hovered = true
		toast.add_theme_stylebox_override("panel", hover))
	toast.mouse_exited.connect(func() -> void:
		a.hovered = false
		toast.add_theme_stylebox_override("panel", normal))
	toast.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_LEFT:
				_go(a)
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				_remove(key)
				_layout()
			toast.accept_event())


# Camera to the alert's next target and select / open it.
func _go(a: Dictionary) -> void:
	if a.targets.is_empty():
		Game.set_building(true)  # material: the plans live in build mode
		return
	var t = a.targets[a.next % a.targets.size()]
	a.next += 1
	var main := get_parent()
	if t is Worker:
		main.get_node("TopBar")._focus(t)
	elif t is Vector3i:  # workstation
		_look(main, Vector3(t))
		get_tree().get_first_node_in_group("station_panel").open(t)
	else:  # stockpile zone
		var tiles: Array = t.tiles.keys()
		if tiles:
			_look(main, Vector3(tiles[tiles.size() / 2]))


func _look(main: Node, at: Vector3) -> void:
	main.get_node("CameraRig").position = at
	Game.world.cut_to(at)
	Game.mode_changed.emit()
