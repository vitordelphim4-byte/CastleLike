extends PanelContainer
## RimWorld-style work tab: one row per villager, one column per work type.
## Cell = priority: 1 (does it first) .. 4 (last), "-" = never. Left click: 1→2→3→4→-→1, right click: reverse.

const CYCLE := [1, 2, 3, 4, 0]
const LEVEL_COLORS := {1: Color(0.4, 1, 0.4), 2: Color(1, 0.9, 0.4), 3: Color(0.85, 0.85, 0.85), 4: Color(0.6, 0.6, 0.6), 0: Color(0.45, 0.45, 0.45)}

var grid := GridContainer.new()


func _ready() -> void:
	add_to_group("work_tab")
	UiDrag.attach(self)
	visible = false
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "Trabalho — 1 = faz primeiro, 4 = por último, - = nunca  (clique esq./dir. muda)"
	box.add_child(title)
	box.add_child(grid)


func toggle() -> void:
	visible = not visible
	if visible:
		_rebuild()


func _rebuild() -> void:
	for c in grid.get_children():
		c.queue_free()
	grid.columns = Game.WORKS.size() + 1
	grid.add_child(_label("Aldeão"))
	for work: String in Game.WORKS:
		grid.add_child(_label(Game.WORKS[work]))
	for w: Worker in get_tree().get_nodes_in_group("workers"):
		var name_label := _label(w.worker_name)
		name_label.modulate = w.color
		grid.add_child(name_label)
		for work: String in Game.WORKS:
			var b := Button.new()
			b.custom_minimum_size = Vector2(110, 32)
			b.focus_mode = Control.FOCUS_NONE
			b.gui_input.connect(_on_cell_input.bind(b, w, work))
			_paint(b, w.priorities[work])
			grid.add_child(b)


func _on_cell_input(e: InputEvent, b: Button, w: Worker, work: String) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var step := 1 if e.button_index == MOUSE_BUTTON_LEFT else -1
		var i := (CYCLE.find(w.priorities[work]) + step + CYCLE.size()) % CYCLE.size()
		w.priorities[work] = CYCLE[i]
		_paint(b, CYCLE[i])
		accept_event()


func _paint(b: Button, level: int) -> void:
	b.text = str(level) if level > 0 else "-"
	b.add_theme_color_override("font_color", LEVEL_COLORS[level])
	b.add_theme_color_override("font_hover_color", LEVEL_COLORS[level])


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(110, 0)
	return l
