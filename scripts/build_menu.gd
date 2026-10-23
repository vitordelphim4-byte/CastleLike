extends PanelContainer
## Castle Story-style build menu (left side, shown in build mode): pieces grouped by material with
## 3D thumbnails, the automatic roof tool and the tool bar (build / demolish / rotate / height).

const GOLD := Color(0.95, 0.75, 0.3)
const DIR_NAMES := ["norte", "leste", "sul", "oeste"]  # matches Game.ROT_DIRS

var buttons := {}  # item -> Button
var tool_buttons := {}  # tool -> Button
var roof_buttons := {}  # "type:gable" / "mat:wood" / "overhang" -> Button
var status := Label.new()


func _ready() -> void:
	visible = false
	add_theme_stylebox_override("panel", panel_style())
	var box := VBoxContainer.new()
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := _label("Construção", 26, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_button(head, "X", func() -> void: Game.set_building(false)).flat = true

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(320, 0)
	box.add_child(scroll)
	var list := VBoxContainer.new()
	scroll.add_child(list)
	for group: String in Pieces.GROUPS:
		list.add_child(_label(group, 17, GOLD))
		if group == "Telhado":
			_roof_tool(list)
		var grid := GridContainer.new()
		grid.columns = 4
		list.add_child(grid)
		for item: String in Pieces.ITEMS:
			var info: Dictionary = Pieces.ITEMS[item]
			if info.group != group:
				continue
			var b := _button(grid, "", _pick.bind(item))
			b.icon = Game.preview(item)
			b.expand_icon = true
			b.custom_minimum_size = Vector2(72, 72)
			b.toggle_mode = true
			b.tooltip_text = "%s\nCusto: %d %s" % [info.name, info.cost, Game.RESOURCES[info.mat].name]
			buttons[item] = b

	box.add_child(HSeparator.new())
	var tools := HBoxContainer.new()
	box.add_child(tools)
	tool_buttons.build = _button(tools, "Construir", _set_tool.bind("build"))
	tool_buttons.demolish = _button(tools, "Demolir (X)", _set_tool.bind("demolish"))
	_button(tools, "Girar (R)", func() -> void:
		Game.build_rot = (Game.build_rot + 1) % Game.ROT_DIRS.size()
		Game.mode_changed.emit())
	var height := HBoxContainer.new()
	box.add_child(height)
	height.add_child(_label("Altura", 15, Color.WHITE))
	_button(height, " - ", _height.bind(-1))
	_button(height, " + ", _height.bind(1))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	status.custom_minimum_size = Vector2(300, 0)
	box.add_child(status)
	for b in tool_buttons.values() + roof_buttons.values():
		b.toggle_mode = true
	Game.mode_changed.connect(_refresh)
	_refresh()


# "Telhado automático": pick type, material, overhang, then drag over a building's wall tops.
func _roof_tool(parent: Node) -> void:
	tool_buttons.roof = _button(parent, "Telhado automático — arraste sobre as paredes", _set_tool.bind("roof"))
	var types := HBoxContainer.new()
	parent.add_child(types)
	for t: String in Roofs.TYPES:
		roof_buttons["type:" + t] = _button(types, Roofs.TYPES[t], _roof_set.bind("roof_type", t))
	var mats := HBoxContainer.new()
	parent.add_child(mats)
	roof_buttons["mat:wood"] = _button(mats, "Telha (madeira)", _roof_set.bind("roof_mat", "wood"))
	roof_buttons["mat:stone"] = _button(mats, "Ardósia (pedra)", _roof_set.bind("roof_mat", "stone"))
	roof_buttons.overhang = _button(mats, "Beiral", func() -> void:
		Game.roof_overhang = not Game.roof_overhang
		Game.mode_changed.emit())
	parent.add_child(_label("Peças avulsas, para ajustar à mão:", 13, Color(0.8, 0.8, 0.8)))


static func panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.09, 0.09, 0.09, 0.93)
	s.border_color = GOLD
	s.border_width_right = 2
	s.set_content_margin_all(10)
	return s


func _refresh() -> void:
	visible = Game.building
	for item in buttons:
		buttons[item].set_pressed_no_signal(item == Game.build_item and Game.build_tool == "build")
	for t in tool_buttons:
		tool_buttons[t].set_pressed_no_signal(t == Game.build_tool)
	for key: String in roof_buttons:
		var on: bool = Game.roof_overhang if key == "overhang" else \
			(key == "type:" + Game.roof_type or key == "mat:" + Game.roof_mat)
		roof_buttons[key].set_pressed_no_signal(on)
	var info: Dictionary = Pieces.ITEMS[Game.build_item]
	match Game.build_tool:
		"demolish":
			status.text = "Demolir: arraste sobre construções. Os aldeões com Construção desmontam e devolvem o material."
		"roof":
			status.text = "Telhado %s em %s%s\nArraste do canto de uma parede ao canto oposto. R gira a cumeeira. " \
				% [Roofs.TYPES[Game.roof_type].to_lower(), "telha" if Game.roof_mat == "wood" else "ardósia",
				", com beiral" if Game.roof_overhang else ""] \
				+ "Se não houver como subir, uma escada é planejada junto."
		_:
			var height: String = str(Game.build_height) if Pieces.stacks(Game.build_item) else "1 (peça única)"
			status.text = "%s — custa %d %s\nAltura: %s   Direção: %s" % [info.name, info.cost,
				Game.RESOURCES[info.mat].name, height, DIR_NAMES[Game.build_rot]]


func _pick(item: String) -> void:
	Game.build_item = item
	Game.build_tool = "build"
	if not Pieces.stacks(item):
		Game.build_height = 1
	Game.mode_changed.emit()


func _set_tool(t: String) -> void:
	Game.build_tool = t
	Game.mode_changed.emit()


func _roof_set(field: String, value: String) -> void:
	Game.set(field, value)
	Game.build_tool = "roof"
	Game.mode_changed.emit()


func _height(step: int) -> void:
	Game.build_height = clampi(Game.build_height + step, 1, 10)
	Game.mode_changed.emit()


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	parent.add_child(b)
	return b


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l
