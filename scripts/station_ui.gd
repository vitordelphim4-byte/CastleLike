extends PanelContainer
## Workstation panel (click a station), HUD mock layout: per recipe its inputs, the bill mode
## (off / repeat forever / make until the stockpile has N, with a − N + field) and a status line with
## an icon: who is working and how far along, or why it isn't being worked.

const STATION_ICONS := {"kiln": "charcoal", "furnace": "iron"}  # resource icon standing for the station
const MODE_SHORT := {"off": "Desligado", "forever": "Repetir", "until": "Até ter N"}

var base := Vector3i.ZERO
var box := VBoxContainer.new()
var rows := {}  # recipe -> {modes: Array[Button], target: Control, value: Label, icon, status, bar, count}


func _ready() -> void:
	add_to_group("station_panel")
	UiDrag.attach(self)
	visible = false
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var t := Timer.new()
	t.wait_time = 0.5
	t.ignore_time_scale = true
	t.autostart = true
	t.timeout.connect(_refresh_status)
	add_child(t)


func open(at: Vector3i) -> void:
	var st := Game.station(at)
	if st.is_empty():
		return
	base = at
	var villager := get_tree().get_first_node_in_group("villager_panel")
	if villager:
		villager.close()  # same spot on screen
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	rows.clear()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	var icon := TextureRect.new()
	icon.texture = UiIcons.x2(UiIcons.resource(STATION_ICONS.get(st.item, "iron")))
	head.add_child(icon)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var title := Label.new()
	title.text = Crafting.STATIONS[st.item].name
	title.add_theme_font_override("font", UiTheme.BOLD)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	titles.add_child(title)
	titles.add_child(UiTheme.caption("Estação de trabalho"))
	var x := UiTheme.icon_button(UiIcons.glyph("close"), "Fechar", 24)
	x.pressed.connect(close)
	head.add_child(x)
	var note := PanelContainer.new()
	note.add_theme_stylebox_override("panel", UiTheme.parchment(false))
	box.add_child(note)
	var info := Label.new()
	info.text = Crafting.STATIONS[st.item].info
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.custom_minimum_size.x = 380
	info.add_theme_color_override("font_color", UiTheme.INK)
	note.add_child(info)
	box.add_child(UiTheme.caption("RECEITAS"))
	for id: String in st.bills:
		_recipe(id, st.bills[id])
	visible = true
	_refresh_status()


func _recipe(id: String, bill: Dictionary) -> void:
	var well := PanelContainer.new()
	var style := UiTheme.well()
	style.set_content_margin_all(10)
	well.add_theme_stylebox_override("panel", style)
	box.add_child(well)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	well.add_child(v)
	var recipe: Dictionary = Crafting.RECIPES[id]
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)
	var product := TextureRect.new()
	product.texture = UiIcons.resource(Crafting.product(id))
	product.custom_minimum_size = Vector2(22, 22)
	product.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top.add_child(product)
	var name_l := Label.new()
	name_l.text = recipe.name
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	top.add_child(UiTheme.caption("usa"))
	for kind: String in recipe.in:
		var n := UiTheme.num(18)
		n.text = str(recipe.in[kind])
		top.add_child(n)
		var ing := TextureRect.new()
		ing.texture = UiIcons.resource(kind)
		ing.tooltip_text = Game.RESOURCES[kind].name
		top.add_child(ing)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 0)
	v.add_child(line)
	var modes: Array[Button] = []
	for m: String in Crafting.MODES:
		var b := Button.new()
		b.text = MODE_SHORT[m]
		b.tooltip_text = Crafting.MODE_NAMES[m]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			bill.mode = m
			_refresh_status())
		line.add_child(b)
		modes.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(spacer)
	var target := HBoxContainer.new()
	target.add_theme_constant_override("separation", 4)
	line.add_child(target)
	var value := UiTheme.num(22)
	var minus := Button.new()
	minus.text = "−"
	var field := PanelContainer.new()
	field.add_theme_stylebox_override("panel", UiTheme.well())
	field.custom_minimum_size = Vector2(44, 26)
	field.tooltip_text = "Roda do mouse: ±1 (Shift: ±10)"
	field.mouse_filter = Control.MOUSE_FILTER_STOP
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.add_child(value)
	var plus := Button.new()
	plus.text = "+"
	for b: Button in [minus, plus]:
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(24, 26)
	minus.pressed.connect(_step.bind(bill, -1))
	plus.pressed.connect(_step.bind(bill, 1))
	field.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_step(bill, (1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -1) * (10 if e.shift_pressed else 1))
			field.accept_event())
	target.add_child(minus)
	target.add_child(field)
	target.add_child(plus)

	var status_line := HBoxContainer.new()
	status_line.add_theme_constant_override("separation", 8)
	v.add_child(status_line)
	var icon := TextureRect.new()
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_line.add_child(icon)
	var status := Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.clip_text = true
	status_line.add_child(status)
	var bar := UiTheme.bar(100, 8, UiTheme.OK)
	status_line.add_child(bar)
	var count := UiTheme.num(18)
	count.custom_minimum_size.x = 44
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_line.add_child(count)
	rows[id] = {"modes": modes, "target": target, "value": value, "icon": icon, "status": status, "bar": bar,
		"count": count}


func _step(bill: Dictionary, by: int) -> void:
	bill.target = clampi(bill.target + by, 1, 999)
	_refresh_status()


func close() -> void:
	visible = false


func _refresh_status() -> void:
	if not visible:
		return
	var st := Game.station(base)
	if st.is_empty():
		close()  # demolished
		return
	var worker: Worker = null
	for w: Worker in get_tree().get_nodes_in_group("workers"):
		if w.job_kind == "craft" and w.job_cell == base:
			worker = w
	for id: String in rows:
		var r: Dictionary = rows[id]
		var bill: Dictionary = st.bills[id]
		for i in r.modes.size():
			r.modes[i].set_pressed_no_signal(Crafting.MODES[i] == bill.mode)
		r.target.visible = bill.mode == "until"
		r.value.text = str(bill.target)
		var have: int = Game.stock[Crafting.product(id)]
		var why := Crafting.blocker(bill, id)
		var here := worker != null and worker.job_recipe == id
		if why != "":
			var icon := "stop" if bill.mode == "off" else ("ok" if why == "meta atingida" else "warn")
			r.icon.texture = UiIcons.x2(UiIcons.glyph(icon))
			r.status.text = "Parado: " + why
		elif here:
			r.icon.texture = UiIcons.x2(UiIcons.glyph("ok"))
			r.status.text = "Trabalhando · " + worker.worker_name
		else:
			r.icon.texture = UiIcons.x2(UiIcons.glyph("warn"))
			r.status.text = "Esperando um aldeão com Artesão livre"
		if here and worker.state == Worker.WORKING:  # batch progress
			var p: float = 1.0 - worker.timer / Crafting.RECIPES[id].time
			r.bar.max_value = 1.0
			r.bar.value = p
			r.count.text = "%d%%" % int(p * 100)
		elif bill.mode == "until":  # stockpile toward the target
			r.bar.max_value = bill.target
			r.bar.value = mini(have, bill.target)
			r.count.text = "%d/%d" % [have, bill.target]
		else:
			r.bar.value = 0
			r.count.text = str(have)
		r.bar.tooltip_text = "No estoque: %d" % have
