extends VBoxContainer
## Left panel (HUD mock): Work and Build buttons, new-order buttons, then the active orders, stockpiles
## and farms with what each still has to do. Numbers that change on their own refresh every second.

const SHORT := {"wood": "Cortar", "gather": "Colher", "hunt": "Caçar", "dig": "Escavar", "stock": "Estoque",
	"farm": "Plantação"}
const STOCK_FILL := Color("#D9B44A")

var _live: Array[Callable] = []  # refreshers for numbers that change without a rebuild


func _ready() -> void:
	UiDrag.attach(get_parent())  # OrdersPanel
	custom_minimum_size.x = 284  # 320 with the frame
	add_theme_constant_override("separation", 8)
	Game.orders_changed.connect(_rebuild)
	Game.mode_changed.connect(func() -> void: get_parent().visible = not Game.building)  # build menu takes this spot
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.ignore_time_scale = true
	t.timeout.connect(_refresh)
	add_child(t)
	_rebuild()


func _rebuild() -> void:
	_live.clear()
	for c in get_children():
		if c is Control:
			remove_child(c)
			c.queue_free()
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	add_child(top)
	_key_button(top, "Trabalho", "T", func() -> void: get_tree().get_first_node_in_group("work_tab").toggle())
	_key_button(top, "Construção", "B", func() -> void: Game.set_building(not Game.building))

	add_child(UiTheme.caption("NOVA ORDEM"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)
	for kind: String in Game.ORDER_NAMES:
		var b := Button.new()
		b.text = SHORT[kind]
		b.icon = UiIcons.x2(UiIcons.order(kind))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = Game.ORDER_NAMES[kind]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 36
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(Game.start_area.bind(kind))
		grid.add_child(b)

	if Game.orders:
		var head := HBoxContainer.new()
		add_child(head)
		var cap := UiTheme.caption("ORDENS ATIVAS")
		cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(cap)
		var n := UiTheme.num(16, UiTheme.TEXT_DIM)
		n.text = str(Game.orders.size())
		head.add_child(n)
		var list := _well()
		for o in Game.orders:
			_order_row(list, o)
	if Game.zones:
		add_child(UiTheme.caption("ESTOQUES"))
		var list := _well()
		for z in Game.zones:
			_zone_row(list, z)
	if Game.farms:
		add_child(UiTheme.caption("PLANTAÇÕES"))
		var list := _well()
		for f in Game.farms:
			_farm_row(list, f)
	_refresh()


func _refresh() -> void:
	for f in _live:
		f.call()


func _order_row(list: Container, o: Dictionary) -> void:
	var row := _row(list, o.kind, o.id)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	var name_label := Label.new()
	name_label.text = Game.ORDER_NAMES[o.kind]
	name_label.add_theme_color_override("font_color", UiTheme.TEXT_OFF if o.paused else UiTheme.TEXT)
	name_label.clip_text = true
	v.add_child(name_label)
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	info.clip_text = true
	v.add_child(info)
	_live.append(func() -> void: info.text = ("Pausada · " if o.paused else "") + Game.order_info(o))
	_action(row, "resume" if o.paused else "pause", "Retomar" if o.paused else "Pausar", Game.toggle_pause.bind(o))
	_action(row, "edit", "Editar área", Game.start_area.bind(o.kind, o))
	_action(row, "close", "Remover", Game.remove_order.bind(o))


func _zone_row(list: Container, z: Dictionary) -> void:
	var row := _row(list, "stock", z.id)
	var name_label := Label.new()
	name_label.text = "Estoque"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var full := TextureRect.new()
	full.texture = UiIcons.x2(UiIcons.glyph("warn"))
	full.tooltip_text = "Estoque cheio"
	full.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(full)
	var b := UiTheme.bar(64, 8, STOCK_FILL)
	row.add_child(b)
	var count := UiTheme.num(18)
	count.custom_minimum_size.x = 40
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.tooltip_text = "Quadrados ocupados / total. Cada quadrado guarda um tipo de recurso."
	count.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(count)
	_live.append(func() -> void:
		var used := Game.zone_used(z)
		b.max_value = z.tiles.size()
		b.value = used
		count.text = "%d/%d" % [used, z.tiles.size()]
		full.visible = used >= z.tiles.size())
	_action(row, "edit", "Editar área", Game.start_area.bind("stock", z))
	_action(row, "close", "Remover", Game.remove_zone.bind(z))


func _farm_row(list: Container, f: Dictionary) -> void:
	var row := _row(list, "farm", f.id)
	var crop: Dictionary = Farming.CROPS[f.crop]
	var pick := Button.new()
	pick.text = crop.name + " ▸"
	pick.focus_mode = Control.FOCUS_NONE
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.tooltip_text = "Cultura plantada aqui (clique troca). %s: pronto em %.1f dia(s), %d por quadrado." \
		% [crop.name, crop.grow_days, crop.yield]
	pick.pressed.connect(Game.cycle_crop.bind(f))
	row.add_child(pick)
	var b := UiTheme.bar(44, 8, UiTheme.OK)
	b.tooltip_text = "Quadrados maduros"
	row.add_child(b)
	var count := UiTheme.num(18)
	count.custom_minimum_size.x = 40
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(count)
	_live.append(func() -> void:
		var ripe := Game.farm_ripe(f)
		b.max_value = f.tiles.size()
		b.value = ripe
		count.text = "%d/%d" % [ripe, f.tiles.size()])
	_action(row, "edit", "Editar área", Game.start_area.bind("farm", f))
	_action(row, "close", "Remover", Game.remove_farm.bind(f))


# Sunken list box under a caption.
func _well() -> VBoxContainer:
	var box := PanelContainer.new()
	var style := UiTheme.well()
	style.set_content_margin_all(4)
	box.add_theme_stylebox_override("panel", style)
	add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	box.add_child(v)
	return v


# Row start: kind icon + "#id".
func _row(list: Container, kind: String, id: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size.y = 32
	list.add_child(row)
	var icon := TextureRect.new()
	icon.texture = UiIcons.x2(UiIcons.order(kind))
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var n := UiTheme.num(18, UiTheme.TEXT_DIM)
	n.text = "#%d" % id
	n.custom_minimum_size.x = 26
	row.add_child(n)
	return row


func _action(row: Container, glyph: String, tip: String, callback: Callable) -> void:
	var b := UiTheme.icon_button(UiIcons.glyph(glyph), tip)
	b.pressed.connect(callback)
	row.add_child(b)


func _key_button(parent: Container, text: String, key: String, callback: Callable) -> void:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 32
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(callback)
	parent.add_child(b)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(h)
	var l := Label.new()
	l.text = text
	h.add_child(l)
	h.add_child(UiTheme.key_label(key))
