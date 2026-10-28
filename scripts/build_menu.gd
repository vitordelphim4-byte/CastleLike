extends PanelContainer
## Castle Story-style build menu (left side, shown in build mode), HUD mock layout: title, tool buttons
## (build / demolish / rotate) and height, one tab per piece group with 3D thumbnails (the roof tab
## also has the automatic roof tool), and a parchment status box for the current piece.

const GOLD := UiTheme.GOLD
const DIR_NAMES := ["norte", "leste", "sul", "oeste"]  # matches Game.ROT_DIRS

var buttons := {}  # item -> Button
var tool_buttons := {}  # tool -> Button
var roof_buttons := {}  # "type:gable" / "mat:wood" / "overhang" -> Button
var tabs := {}  # group -> tab Button
var pages := {}  # group -> its page (Control)
var tab := ""
var height_label := UiTheme.num(22)
var status_title := Label.new()
var status := Label.new()


func _ready() -> void:
	visible = false
	UiDrag.attach(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var title := _label("Construção", 24, GOLD)
	title.add_theme_font_override("font", UiTheme.BOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UiTheme.key_label("B"))
	var close := UiTheme.icon_button(UiIcons.glyph("close"), "Sair do modo construção (B / Esc)")
	close.pressed.connect(Game.set_building.bind(false))
	head.add_child(close)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	box.add_child(tools)
	tool_buttons.build = _tool(tools, "build", "Construir", "", _set_tool.bind("build"))
	tool_buttons.demolish = _tool(tools, "demolish", "Demolir", "X", _set_tool.bind("demolish"))
	_tool(tools, "rotate", "Girar", "R", func() -> void:
		Game.build_rot = (Game.build_rot + 1) % Game.ROT_DIRS.size()
		Game.mode_changed.emit())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(spacer)
	var height := VBoxContainer.new()
	height.add_theme_constant_override("separation", 2)
	tools.add_child(height)
	var cap := UiTheme.caption("ALTURA")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	height.add_child(cap)
	var spin := HBoxContainer.new()
	spin.add_theme_constant_override("separation", 4)
	height.add_child(spin)
	_button(spin, "−", _height.bind(-1)).custom_minimum_size = Vector2(26, 26)
	var field := PanelContainer.new()
	field.add_theme_stylebox_override("panel", UiTheme.well())
	field.custom_minimum_size = Vector2(34, 26)
	height_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.add_child(height_label)
	spin.add_child(field)
	_button(spin, "+", _height.bind(1)).custom_minimum_size = Vector2(26, 26)

	var tab_grid := GridContainer.new()  # 6 groups: two rows of 3 (one row would not fit 320 px)
	tab_grid.columns = 3
	tab_grid.add_theme_constant_override("h_separation", 2)
	tab_grid.add_theme_constant_override("v_separation", 2)
	box.add_child(tab_grid)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(294, 0)
	box.add_child(scroll)
	var stack := VBoxContainer.new()
	scroll.add_child(stack)
	for group: String in Pieces.GROUPS:
		var t := _button(tab_grid, group, _show_tab.bind(group))
		t.toggle_mode = true
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs[group] = t
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 8)
		stack.add_child(page)
		pages[group] = page
		if group == "Telhado":
			_roof_tool(page)
		var grid := GridContainer.new()
		grid.columns = 4
		page.add_child(grid)
		for item: String in Pieces.ITEMS:
			var info: Dictionary = Pieces.ITEMS[item]
			if info.group != group:
				continue
			var b := _button(grid, "", _pick.bind(item))
			b.icon = Game.preview(item)
			b.expand_icon = true
			b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # 3D render scaled down
			b.custom_minimum_size = Vector2(70, 70)
			b.toggle_mode = true
			b.tooltip_text = "%s\nCusto: %d %s" % [info.name, info.cost, Game.RESOURCES[info.mat].name]
			buttons[item] = b

	var note := PanelContainer.new()
	note.add_theme_stylebox_override("panel", UiTheme.parchment(false))
	box.add_child(note)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	note.add_child(lines)
	status_title.add_theme_font_override("font", UiTheme.BOLD)
	status_title.add_theme_color_override("font_color", UiTheme.INK)
	lines.add_child(status_title)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	status.custom_minimum_size = Vector2(260, 0)
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", UiTheme.INK)
	lines.add_child(status)
	for b in roof_buttons.values():
		b.toggle_mode = true
	Game.mode_changed.connect(_refresh)
	_show_tab(Pieces.ITEMS[Game.build_item].group)


# "Telhado automático": pick type, material, overhang, then drag over a building's wall tops.
func _roof_tool(parent: Node) -> void:
	parent.add_child(UiTheme.caption("TELHADO AUTOMÁTICO"))
	tool_buttons.roof = _button(parent, "Arrastar sobre as paredes", _set_tool.bind("roof"))
	tool_buttons.roof.toggle_mode = true
	var types := HBoxContainer.new()
	parent.add_child(types)
	for t: String in Roofs.TYPES:
		roof_buttons["type:" + t] = _button(types, Roofs.TYPES[t], _roof_set.bind("roof_type", t))
	var mats := HBoxContainer.new()
	parent.add_child(mats)
	roof_buttons["mat:wood"] = _button(mats, "Telha", _roof_set.bind("roof_mat", "wood"))
	roof_buttons["mat:wood"].tooltip_text = "Telha de madeira"
	roof_buttons["mat:stone"] = _button(mats, "Ardósia", _roof_set.bind("roof_mat", "stone"))
	roof_buttons["mat:stone"].tooltip_text = "Ardósia de pedra"
	roof_buttons.overhang = _button(mats, "Beiral", func() -> void:
		Game.roof_overhang = not Game.roof_overhang
		Game.mode_changed.emit())
	parent.add_child(UiTheme.caption("PEÇAS AVULSAS, PARA AJUSTAR À MÃO"))


func _show_tab(group: String) -> void:
	tab = group
	for g: String in pages:
		pages[g].visible = g == group
		tabs[g].set_pressed_no_signal(g == group)


func _refresh() -> void:
	var was_visible := visible
	visible = Game.building
	if visible and not was_visible:  # opening: show the current piece's group
		_show_tab(Pieces.ITEMS[Game.build_item].group)
	for item in buttons:
		buttons[item].set_pressed_no_signal(item == Game.build_item and Game.build_tool == "build")
	for t in tool_buttons:
		tool_buttons[t].set_pressed_no_signal(t == Game.build_tool)
	for key: String in roof_buttons:
		var on: bool = Game.roof_overhang if key == "overhang" else \
			(key == "type:" + Game.roof_type or key == "mat:" + Game.roof_mat)
		roof_buttons[key].set_pressed_no_signal(on)
	var info: Dictionary = Pieces.ITEMS[Game.build_item]
	var stacks := Pieces.stacks(Game.build_item)
	height_label.text = str(Game.build_height) if stacks else "1"
	match Game.build_tool:
		"demolish":
			status_title.text = "Demolir"
			status.text = "Arraste sobre construções. Os aldeões com Construção desmontam e devolvem o material."
		"roof":
			status_title.text = "Telhado %s em %s%s" % [Roofs.TYPES[Game.roof_type].to_lower(),
				"telha" if Game.roof_mat == "wood" else "ardósia", ", com beiral" if Game.roof_overhang else ""]
			status.text = "Arraste do canto de uma parede ao canto oposto. R gira a cumeeira. " \
				+ "Se não houver como subir, uma escada é planejada junto."
		_:
			status_title.text = info.name
			status.text = "%d %s por peça · altura %s · direção %s" % [info.cost, Game.RESOURCES[info.mat].name,
				str(Game.build_height) if stacks else "1 (peça única)", DIR_NAMES[Game.build_rot]]


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


# 44x44 tool button with its pixel icon and the shortcut key in the corner.
func _tool(parent: Node, glyph: String, tip: String, key: String, callback: Callable) -> Button:
	var b := UiTheme.icon_button(UiIcons.glyph(glyph), tip + (" (%s)" % key if key else ""), 44)
	b.toggle_mode = glyph != "rotate"
	b.pressed.connect(callback)
	parent.add_child(b)
	if key:
		var k := UiTheme.key_label(key)
		k.custom_minimum_size = Vector2(14, 16)
		k.add_theme_font_size_override("font_size", 14)
		k.position = Vector2(34, 32)
		b.add_child(k)
	return b


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
