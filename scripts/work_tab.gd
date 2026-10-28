extends PanelContainer
## RimWorld-style work tab (HUD mock): one row per villager, one column per work type.
## Cell = priority: 1 (does it first) .. 4 (last), "–" = never. Left click: 1→2→3→4→–→1, right click: reverse.

const CYCLE := [1, 2, 3, 4, 0]
const NAME_W := 164
const CELL_W := 72

var rows := VBoxContainer.new()


func _ready() -> void:
	add_to_group("work_tab")
	UiDrag.attach(self)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var title := Label.new()
	title.text = "Trabalho"
	title.add_theme_font_override("font", UiTheme.BOLD)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UiTheme.key_label("T"))
	var close := UiTheme.icon_button(UiIcons.glyph("close"), "Fechar (T)", 24)
	close.pressed.connect(toggle)
	head.add_child(close)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 0)
	box.add_child(columns)
	var who := UiTheme.caption("ALDEÃO")
	who.custom_minimum_size.x = NAME_W
	who.size_flags_vertical = Control.SIZE_SHRINK_END
	columns.add_child(who)
	for work: String in Game.WORKS:
		var col := VBoxContainer.new()
		col.custom_minimum_size.x = CELL_W
		col.add_theme_constant_override("separation", 4)
		columns.add_child(col)
		var icon := TextureRect.new()
		icon.texture = UiIcons.x2(UiIcons.job(work))
		icon.custom_minimum_size = Vector2(32, 32)  # tool glyphs are smaller than resource icons
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		col.add_child(icon)
		var l := UiTheme.caption(Game.WORKS[work])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)

	var well := PanelContainer.new()
	var style := UiTheme.well()
	style.set_content_margin_all(4)
	well.add_theme_stylebox_override("panel", style)
	box.add_child(well)
	rows.add_theme_constant_override("separation", 0)
	well.add_child(rows)
	var legend := HBoxContainer.new()
	box.add_child(legend)
	var a := UiTheme.caption("1 = faz primeiro · 4 = por último · – = nunca")
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.add_child(a)
	legend.add_child(UiTheme.caption("clique esq. / dir. muda"))


func toggle() -> void:
	visible = not visible
	if visible:
		_rebuild()


func _rebuild() -> void:
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	var i := 0
	for w: Worker in get_tree().get_nodes_in_group("workers"):
		var row := PanelContainer.new()
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color("#34221A") if i % 2 else UiTheme.PANEL_BG
		row.add_theme_stylebox_override("panel", bg)
		rows.add_child(row)
		i += 1
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 0)
		row.add_child(h)
		var who := HBoxContainer.new()
		who.custom_minimum_size.x = NAME_W
		who.add_theme_constant_override("separation", 6)
		h.add_child(who)
		var swatch := ColorRect.new()
		swatch.color = w.color
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		who.add_child(swatch)
		var name_label := Label.new()
		name_label.text = w.worker_name
		name_label.add_theme_color_override("font_color", w.color.lightened(0.25))
		who.add_child(name_label)
		for work: String in Game.WORKS:
			var cell := CenterContainer.new()
			cell.custom_minimum_size = Vector2(CELL_W, 26)
			h.add_child(cell)
			var b := Button.new()
			b.custom_minimum_size = Vector2(60, 20)
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_override("font", UiTheme.NUM)
			b.add_theme_font_size_override("font_size", 20)
			b.tooltip_text = "%s · %s" % [w.worker_name, Game.WORKS[work]]
			b.gui_input.connect(_on_cell_input.bind(b, w, work))
			_paint(b, w.priorities[work])
			cell.add_child(b)


func _on_cell_input(e: InputEvent, b: Button, w: Worker, work: String) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var step := 1 if e.button_index == MOUSE_BUTTON_LEFT else -1
		var i := (CYCLE.find(w.priorities[work]) + step + CYCLE.size()) % CYCLE.size()
		w.priorities[work] = CYCLE[i]
		_paint(b, CYCLE[i])
		accept_event()


func _paint(b: Button, level: int) -> void:
	b.text = str(level) if level > 0 else "–"
	var normal := UiTheme.prio(level)
	var hover := UiTheme.prio(level, true)
	for s: String in ["normal", "pressed", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(s, normal)
	b.add_theme_stylebox_override("hover", hover)
	var col := UiTheme.prio_font(level)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, col)
