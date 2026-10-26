extends VBoxContainer
## Left panel: mode buttons + standing orders (pause / edit area / remove).


func _ready() -> void:
	Game.orders_changed.connect(_rebuild)
	Game.mode_changed.connect(func() -> void: get_parent().visible = not Game.building)  # build menu takes this spot
	_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_btn(self, "Trabalho (T)", func() -> void: get_tree().get_first_node_in_group("work_tab").toggle())
	_btn(self, "Construção (B)", func() -> void: Game.set_building(not Game.building))
	var add := HBoxContainer.new()
	add_child(add)
	for kind: String in Game.ORDER_NAMES:
		_btn(add, "+ " + Game.ORDER_NAMES[kind], Game.start_area.bind(kind))
	for o in Game.orders:
		var row := HBoxContainer.new()
		add_child(row)
		var label := Label.new()
		label.text = "#%d %s%s" % [o.id, Game.ORDER_NAMES[o.kind], " (%d blocos)" % o.cells.size() if o.kind == "dig" else ""]
		label.modulate = Game.PAUSED_COLOR if o.paused else Game.ORDER_COLORS[o.kind]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		_btn(row, "Retomar" if o.paused else "Pausar", Game.toggle_pause.bind(o))
		_btn(row, "Editar", Game.start_area.bind(o.kind, o))
		_btn(row, "x", Game.remove_order.bind(o))
	for z in Game.zones:
		var row := HBoxContainer.new()
		add_child(row)
		var label := Label.new()
		label.text = "Estoque #%d (%d/%d)" % [z.id, Game.zone_used(z), z.tiles.size()]
		label.tooltip_text = "Quadrados ocupados / total. Cada quadrado guarda 10 madeiras ou 16 pedras."
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.modulate = Game.ORDER_COLORS.stock
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		_btn(row, "Editar", Game.start_area.bind("stock", z))
		_btn(row, "x", Game.remove_zone.bind(z))
	for f in Game.farms:
		var row := HBoxContainer.new()
		add_child(row)
		var label := Label.new()
		label.text = "Plantação #%d (%d maduros/%d)" % [f.id, Game.farm_ripe(f), f.tiles.size()]
		label.modulate = Game.ORDER_COLORS.farm
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var crop: Dictionary = Farming.CROPS[f.crop]
		_btn(row, crop.name + " ▸", Game.cycle_crop.bind(f))
		row.get_child(-1).tooltip_text = "Cultura plantada aqui (clique troca). %s: pronto em %.1f dia(s), %d por quadrado." \
			% [crop.name, crop.grow_days, crop.yield]
		_btn(row, "Editar", Game.start_area.bind("farm", f))
		_btn(row, "x", Game.remove_farm.bind(f))


func _btn(parent: Node, text: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	parent.add_child(b)
