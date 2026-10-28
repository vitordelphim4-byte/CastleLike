extends PanelContainer
## Selected villager panel (right side, the station panel's spot; HUD mock): big portrait, what they're
## doing, hunger, and their own work priorities (editable, same cells as the work tab).
## Opens when exactly one villager gets selected (card or click in the world); × / Esc close it.

const WorkTab := preload("res://scripts/work_tab.gd")
const SHORT := {"build": "Constr.", "dig": "Miner.", "wood": "Lenha", "farm": "Agric.", "gather": "Colet.",
	"hunt": "Caça", "craft": "Artes."}

var worker: Worker
var portrait := TextureRect.new()
var name_label := Label.new()
var activity := Label.new()
var hunger := ProgressBar.new()
var hunger_pct := UiTheme.num(20)
var hunger_word := UiTheme.caption("")
var cells := {}  # work -> Button
var _level := -1


func _ready() -> void:
	add_to_group("villager_panel")
	UiDrag.attach(self)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	box.add_child(top)
	var frame := PanelContainer.new()
	var ring := UiTheme.well()
	ring.set_content_margin_all(2)
	frame.add_theme_stylebox_override("panel", ring)
	top.add_child(frame)
	portrait.custom_minimum_size = Vector2(96, 96)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(portrait)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	var head := HBoxContainer.new()
	info.add_child(head)
	name_label.add_theme_font_override("font", UiTheme.BOLD)
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var x := UiTheme.icon_button(UiIcons.glyph("close"), "Fechar (Esc)", 24)
	x.pressed.connect(close)
	head.add_child(x)
	info.add_child(_field("AGORA", activity))
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 8)
	hunger.custom_minimum_size = Vector2(160, 12)
	hunger.max_value = 1.0
	hunger.show_percentage = false
	hunger.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(hunger)
	bar_row.add_child(hunger_pct)
	info.add_child(_field("FOME", bar_row))
	hunger_word.text = ""
	var word_row := HBoxContainer.new()
	var pad := Control.new()
	pad.custom_minimum_size.x = 52
	word_row.add_child(pad)
	word_row.add_child(hunger_word)
	info.add_child(word_row)

	var prio_head := HBoxContainer.new()
	prio_head.add_theme_constant_override("separation", 6)
	box.add_child(prio_head)
	var cap := UiTheme.caption("PRIORIDADES DE TRABALHO")
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prio_head.add_child(cap)
	prio_head.add_child(UiTheme.caption("aba completa"))
	prio_head.add_child(UiTheme.key_label("T"))
	var well := PanelContainer.new()
	var style := UiTheme.well()
	style.set_content_margin_all(8)
	well.add_theme_stylebox_override("panel", style)
	box.add_child(well)
	var grid := GridContainer.new()
	grid.name = "Prio"
	grid.columns = Game.WORKS.size()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	well.add_child(grid)
	for work: String in Game.WORKS:
		var l := UiTheme.caption(SHORT.get(work, Game.WORKS[work]))
		l.tooltip_text = Game.WORKS[work]
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size.x = 46
		grid.add_child(l)
	Game.mode_changed.connect(_on_selection)
	var t := Timer.new()
	t.wait_time = 0.25
	t.autostart = true
	t.ignore_time_scale = true
	t.timeout.connect(_refresh)
	add_child(t)


# Caption column (AGORA / FOME) + its content.
func _field(caption: String, content: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var cap := UiTheme.caption(caption)
	cap.custom_minimum_size.x = 44
	row.add_child(cap)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(content)
	return row


func _on_selection() -> void:
	var chosen := get_tree().get_nodes_in_group("workers").filter(func(w: Worker) -> bool: return w.selected)
	if chosen.size() == 1:
		if chosen[0] != worker or not visible:
			open(chosen[0])
	elif visible:
		close()


func open(w: Worker) -> void:
	worker = w
	var station := get_tree().get_first_node_in_group("station_panel")
	if station:
		station.close()  # same spot on screen
	portrait.texture = w.portrait()
	name_label.text = w.worker_name
	name_label.add_theme_color_override("font_color", w.color.lightened(0.25))
	var grid: GridContainer = find_child("Prio", true, false)
	for b in cells.values():
		grid.remove_child(b)
		b.queue_free()
	cells.clear()
	for work: String in Game.WORKS:
		var b := WorkTab.prio_cell(w, work, 46)
		b.custom_minimum_size.y = 22
		grid.add_child(b)
		cells[work] = b
	_level = -1
	visible = true
	_refresh()


func close() -> void:
	visible = false


func _refresh() -> void:
	if not visible:
		return
	if not is_instance_valid(worker):
		close()
		return
	activity.text = worker.activity()
	hunger.value = worker.food
	hunger_pct.text = "%d%%" % roundi(worker.food * 100)
	var level := 0 if worker.food >= Worker.HUNGRY else (1 if worker.food > 0 else 2)
	if level != _level:
		_level = level
		hunger.add_theme_stylebox_override("fill", UiTheme.bar_fill(level))
		hunger_word.text = ["Alimentado", "Com fome", "Faminto"][level]
	for work: String in cells:  # the work tab may have changed them
		WorkTab.paint(cells[work], worker.priorities[work])
