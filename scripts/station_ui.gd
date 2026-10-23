extends PanelContainer
## Workstation panel (click a station): one row per recipe with its bill mode
## (off / repeat forever / make until the stockpile has N) and why it isn't being worked.

var base := Vector3i.ZERO
var box := VBoxContainer.new()
var rows := {}  # recipe -> {mode: OptionButton, target: SpinBox, status: Label}
var title := Label.new()


func _ready() -> void:
	add_to_group("station_panel")
	visible = false
	add_theme_stylebox_override("panel", preload("res://scripts/build_menu.gd").panel_style())
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
	for c in box.get_children():
		c.queue_free()
	rows.clear()
	var head := HBoxContainer.new()
	box.add_child(head)
	title.text = Crafting.STATIONS[st.item].name
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", preload("res://scripts/build_menu.gd").GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if title.get_parent():
		title.get_parent().remove_child(title)
	head.add_child(title)
	var x := Button.new()
	x.text = "X"
	x.flat = true
	x.focus_mode = Control.FOCUS_NONE
	x.pressed.connect(close)
	head.add_child(x)
	var info := Label.new()
	info.text = Crafting.STATIONS[st.item].info
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	box.add_child(info)
	for id: String in st.bills:
		box.add_child(HSeparator.new())
		var bill: Dictionary = st.bills[id]
		var name_l := Label.new()
		name_l.text = "%s:  %s" % [Crafting.RECIPES[id].name, Crafting.describe(id)]
		box.add_child(name_l)
		var line := HBoxContainer.new()
		box.add_child(line)
		var mode := OptionButton.new()
		mode.focus_mode = Control.FOCUS_NONE
		for m: String in Crafting.MODES:
			mode.add_item(Crafting.MODE_NAMES[m])
		mode.selected = Crafting.MODES.find(bill.mode)
		line.add_child(mode)
		var target := SpinBox.new()
		target.min_value = 1
		target.max_value = 999
		target.value = bill.target
		target.suffix = Game.RESOURCES[Crafting.product(id)].name
		target.custom_minimum_size = Vector2(170, 0)
		line.add_child(target)
		var status := Label.new()
		status.add_theme_font_size_override("font_size", 13)
		box.add_child(status)
		mode.item_selected.connect(func(i: int) -> void:
			bill.mode = Crafting.MODES[i]
			_refresh_status())
		target.value_changed.connect(func(v: float) -> void: bill.target = int(v))
		rows[id] = {"mode": mode, "target": target, "status": status}
	visible = true
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
	var worker := ""
	for w: Worker in get_tree().get_nodes_in_group("workers"):
		if w.job_kind == "craft" and w.job_cell == base:
			worker = w.worker_name
	for id: String in rows:
		var bill: Dictionary = st.bills[id]
		rows[id].target.visible = bill.mode == "until"
		var why := Crafting.blocker(bill, id)
		var have := "Estoque: %d" % Game.stock[Crafting.product(id)]
		if worker and why == "":
			rows[id].status.text = "%s · %s está trabalhando aqui" % [have, worker]
		elif why == "":
			rows[id].status.text = "%s · esperando um aldeão com Artesão livre" % have
		else:
			rows[id].status.text = "%s · parado: %s" % [have, why]
		rows[id].status.modulate = Color(0.6, 1, 0.6) if why == "" else Color(1, 0.8, 0.5)
